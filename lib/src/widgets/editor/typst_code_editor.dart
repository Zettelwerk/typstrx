import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart'
    show
        AdaptiveTextSelectionToolbar,
        Colors,
        InkWell,
        ListTile,
        Material,
        Theme,
        desktopTextSelectionControls,
        materialTextSelectionControls;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../document/typst_completion.dart';
import '../../document/typst_tooltip.dart';
import 'typst_editor_controller.dart';

/// How long the mouse must rest over a token before a hover request fires.
const _hoverDebounceDelay = Duration(milliseconds: 300);

Widget _defaultContextMenuBuilder(BuildContext context, EditableTextState editableTextState) {
  if (SystemContextMenu.isSupportedByField(editableTextState)) {
    return SystemContextMenu.editableText(editableTextState: editableTextState);
  }
  return AdaptiveTextSelectionToolbar.editableText(editableTextState: editableTextState);
}

/// Strips `${...}` snippet placeholders from a completion's [apply] text
/// (Typst-ide's own snippet syntax — e.g. `lorem(${})`, `${lhs} + ${rhs}`,
/// or occasionally a numbered `${2:2}` tab-stop), returning the plain text
/// with every placeholder removed and the offset of the first one (or the
/// end of the text, if there were none) for the caret to land on.
///
/// The content between `${` and `}` (a hint name, or a tab-stop number and
/// default) is discarded rather than kept, uniformly for both forms — v1
/// doesn't cycle through multiple tab-stops, so keeping e.g. "lhs" as
/// literal inserted text would be a visible half-measure, not a real
/// feature.
({String text, int caretOffset}) _stripSnippetPlaceholders(String apply) {
  final buffer = StringBuffer();
  int? firstPlaceholderOffset;
  var i = 0;
  while (i < apply.length) {
    if (apply[i] == r'$' && i + 1 < apply.length && apply[i + 1] == '{') {
      final end = apply.indexOf('}', i + 2);
      if (end != -1) {
        firstPlaceholderOffset ??= buffer.length;
        i = end + 1;
        continue;
      }
    }
    buffer.write(apply[i]);
    i++;
  }
  return (text: buffer.toString(), caretOffset: firstPlaceholderOffset ?? buffer.length);
}

/// A Typst source editor built directly on [EditableText], so future editor
/// features (completion popups, hover tooltips) can query caret/selection
/// geometry via [EditableTextState.renderEditable] — access a plain
/// [TextField] does not expose.
///
/// [controller] supplies syntax highlighting, diagnostic squiggles, and
/// auto-closing brackets (see [TypstEditorController]); this widget adds the
/// rest of what a real text field needs on top of bare [EditableText]: focus
/// handling, mouse/touch text selection (tap to place the caret, drag to
/// select, double-tap to select a word — via [TextSelectionGestureDetectorBuilder],
/// the same mechanism [TextField] itself uses), a platform-appropriate
/// selection toolbar, and an I-beam cursor.
///
/// Good defaults, fully overridable: [style] defaults to a monospace font,
/// [expands] defaults to filling the available space, and every other
/// visual/behavioral knob below has a reasonable default but can be set
/// explicitly.
class TypstCodeEditor extends StatefulWidget {
  const TypstCodeEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.style,
    this.cursorColor,
    this.selectionColor,
    this.selectionControls,
    this.autofocus = false,
    this.readOnly = false,
    this.expands = true,
    this.onChanged,
    this.scrollController,
    this.scrollPhysics,
    this.inputFormatters,
    this.contextMenuBuilder = _defaultContextMenuBuilder,
  });

  /// Drives text content, syntax highlighting, diagnostics, and
  /// auto-closing brackets. See [TypstEditorController].
  final TypstEditorController controller;

  /// Focus for this editor. When null, one is created and disposed
  /// internally.
  final FocusNode? focusNode;

  /// Base text style. Highlighting from [controller] layers colors on top
  /// of this per-token; unhighlighted runs (and the font family/size/etc.
  /// for all of them) use this as-is. Defaults to a 13pt monospace font.
  final TextStyle? style;

  /// Caret color. Defaults to [style]'s color, or black if that's also null.
  final Color? cursorColor;

  /// Selection highlight color, shown only while focused. Defaults to a
  /// translucent blue.
  final Color? selectionColor;

  /// Selection handles/toolbar. Defaults to [desktopTextSelectionControls]
  /// on desktop platforms and [materialTextSelectionControls] elsewhere —
  /// a reasonable cross-platform default, not a platform-native match on
  /// every platform (Cupertino styling isn't wired up). Override for that.
  final TextSelectionControls? selectionControls;

  final bool autofocus;
  final bool readOnly;

  /// Whether this editor fills its parent's available space (true, the
  /// default) or grows to fit its content instead — the same choice
  /// [EditableText.expands] offers, exposed because a code editor is
  /// reasonably used either way (a fixed-size pane vs. inline in a
  /// scrolling document).
  final bool expands;

  final ValueChanged<String>? onChanged;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;

  /// Extra formatters applied after [controller]'s own auto-closing-bracket
  /// logic (which lives in [TypstEditorController.set value], not here, so
  /// it can see the edit's full before/after [TextEditingValue] — see that
  /// class for why a [TextInputFormatter] can't safely do this instead).
  final List<TextInputFormatter>? inputFormatters;

  final EditableTextContextMenuBuilder? contextMenuBuilder;

  @override
  State<TypstCodeEditor> createState() => _TypstCodeEditorState();
}

class _TypstCodeEditorState extends State<TypstCodeEditor> implements TextSelectionGestureDetectorBuilderDelegate {
  final GlobalKey<EditableTextState> _editableTextKey = GlobalKey<EditableTextState>();
  late final _gestureDetectorBuilder = TextSelectionGestureDetectorBuilder(delegate: this);

  FocusNode? _internalFocusNode;
  FocusNode get _focusNode => widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  GlobalKey<EditableTextState> get editableTextKey => _editableTextKey;
  @override
  bool get forcePressEnabled => false;
  @override
  bool get selectionEnabled => true;

  // --- completion popup ---
  OverlayEntry? _completionOverlay;
  List<TypstCompletion> _completions = const [];
  int _completionApplyFrom = 0;
  int _selectedCompletionIndex = 0;
  int _completionRequestId = 0;
  String? _lastControllerText;
  TextSelection? _lastControllerSelection;
  FocusNode? _keyHandlerNode;
  FocusOnKeyEventCallback? _previousOnKeyEvent;

  // Set for the duration of _applyCompletion's own `controller.value =`
  // assignment, so _onControllerChanged's synchronous notification from
  // that assignment doesn't dispatch a fresh completions request for the
  // text we just inserted (or, worse, re-show a popup right after the
  // caller picked an item).
  bool _applyingCompletion = false;

  // --- hover tooltip ---
  OverlayEntry? _hoverOverlay;
  TypstTooltip? _hoverTooltip;
  TextPosition? _hoverPosition;
  int _hoverRequestId = 0;
  Timer? _hoverDebounce;

  @override
  void initState() {
    super.initState();
    _lastControllerText = widget.controller.text;
    _lastControllerSelection = widget.controller.selection;
    widget.controller.addListener(_onControllerChanged);
    _installKeyHandler(_focusNode);
  }

  @override
  void didUpdateWidget(TypstCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastControllerText = widget.controller.text;
      _lastControllerSelection = widget.controller.selection;
      _hideCompletionPopup();
      _cancelHover();
    }
    if (oldWidget.focusNode == null && widget.focusNode != null) {
      _internalFocusNode?.dispose();
      _internalFocusNode = null;
    }
    final currentNode = _focusNode;
    if (!identical(_keyHandlerNode, currentNode)) {
      if (_keyHandlerNode != null) _uninstallKeyHandler(_keyHandlerNode!);
      _installKeyHandler(currentNode);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    if (_keyHandlerNode != null) _uninstallKeyHandler(_keyHandlerNode!);
    _completionOverlay?.remove();
    _hoverDebounce?.cancel();
    _hoverOverlay?.remove();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  // A caller-supplied FocusNode's onKeyEvent is chained rather than
  // overwritten, so this doesn't clobber the app's own key handling on it —
  // at the cost that if the caller assigns onKeyEvent again *after* this
  // runs, they clobber ours instead and popup keys stop working. Acceptable:
  // this is an edge case in an already-advanced customization.
  void _installKeyHandler(FocusNode node) {
    _previousOnKeyEvent = node.onKeyEvent;
    node.onKeyEvent = _handleKeyEvent;
    _keyHandlerNode = node;
  }

  void _uninstallKeyHandler(FocusNode node) {
    if (identical(node.onKeyEvent, _handleKeyEvent)) {
      node.onKeyEvent = _previousOnKeyEvent;
    }
    _previousOnKeyEvent = null;
    _keyHandlerNode = null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_completions.isNotEmpty) {
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowDown:
            _moveCompletionSelection(1);
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowUp:
            _moveCompletionSelection(-1);
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.numpadEnter:
          case LogicalKeyboardKey.tab:
            _applyCompletion(_completions[_selectedCompletionIndex]);
            return KeyEventResult.handled;
          case LogicalKeyboardKey.escape:
            _hideCompletionPopup();
            return KeyEventResult.handled;
        }
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.space &&
          HardwareKeyboard.instance.isControlPressed) {
        _requestCompletions(explicit: true);
        return KeyEventResult.handled;
      }
    }
    return _previousOnKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    final text = controller.text;
    final selection = controller.selection;
    final textChanged = text != _lastControllerText;
    final selectionChanged = selection != _lastControllerSelection;
    _lastControllerText = text;
    _lastControllerSelection = selection;
    // Any real text or caret change means whatever was under the mouse
    // when the tooltip was requested is no longer what the tooltip
    // describes — independent of the completion-popup logic below.
    if (textChanged || selectionChanged) _cancelHover();
    if (_applyingCompletion) {
      // Tracking above stays accurate either way; just skip reacting to a
      // change _applyCompletion made itself (see the field's doc comment).
      return;
    }
    if (!textChanged && !selectionChanged) {
      // Genuinely nothing changed — e.g. EditableText re-asserting the same
      // value on the controller for its own bookkeeping. Nothing to react
      // to either way; in particular, not a reason to hide an open popup.
      return;
    }
    if (!textChanged) {
      // A pure selection/caret move (arrow keys, a click, programmatic) —
      // whatever was being offered was for the old position.
      _hideCompletionPopup();
      return;
    }
    if (!selection.isCollapsed) {
      _hideCompletionPopup();
      return;
    }
    _requestCompletions(explicit: false);
  }

  void _requestCompletions({required bool explicit}) {
    final controller = widget.controller;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _hideCompletionPopup();
      return;
    }
    final cursor = selection.baseOffset;
    final requestId = ++_completionRequestId;
    controller.session.completions(cursor, explicit: explicit).then((result) {
      if (!mounted || requestId != _completionRequestId) return;
      // Value-aware analysis (field-access completions) reflects whatever
      // the native side last compiled, not necessarily this live buffer —
      // see TypstSession.lastCompiledSource. If the buffer or the cursor
      // has moved on since this request was dispatched, applying at
      // result.applyFromUtf16 could land at the wrong place, so discard
      // rather than show a result that no longer matches reality. While
      // typing continuously this discards often; the next keystroke's
      // request (or an explicit trigger once compiling catches up) works.
      final stillFresh =
          controller.session.lastCompiledSource == controller.text &&
          controller.selection.isCollapsed &&
          controller.selection.baseOffset == cursor;
      if (!stillFresh) {
        if (explicit) _hideCompletionPopup();
        return;
      }
      final prefix = cursor >= result.applyFromUtf16
          ? controller.text.substring(result.applyFromUtf16, cursor)
          : '';
      final prefixLower = prefix.toLowerCase();
      final filtered = [
        for (final c in result.completions)
          if (c.apply.toLowerCase().startsWith(prefixLower)) c,
      ];
      _completions = filtered;
      _completionApplyFrom = result.applyFromUtf16;
      _selectedCompletionIndex = 0;
      if (filtered.isEmpty) {
        _hideCompletionPopup();
      } else {
        _showCompletionPopup();
      }
    });
  }

  void _moveCompletionSelection(int delta) {
    if (_completions.isEmpty) return;
    final count = _completions.length;
    _selectedCompletionIndex = (_selectedCompletionIndex + delta) % count;
    if (_selectedCompletionIndex < 0) _selectedCompletionIndex += count;
    _completionOverlay?.markNeedsBuild();
  }

  void _applyCompletion(TypstCompletion item) {
    final controller = widget.controller;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed || selection.baseOffset < _completionApplyFrom) {
      _hideCompletionPopup();
      return;
    }
    final cursor = selection.baseOffset;
    final stripped = _stripSnippetPlaceholders(item.apply);
    final text = controller.text;
    final newText = text.replaceRange(_completionApplyFrom, cursor, stripped.text);
    _applyingCompletion = true;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: _completionApplyFrom + stripped.caretOffset),
    );
    _applyingCompletion = false;
    _hideCompletionPopup();
  }

  void _showCompletionPopup() {
    if (_completionOverlay == null) {
      _completionOverlay = OverlayEntry(builder: _buildCompletionOverlay);
      Overlay.of(context).insert(_completionOverlay!);
    } else {
      _completionOverlay!.markNeedsBuild();
    }
  }

  void _hideCompletionPopup() {
    _completionOverlay?.remove();
    _completionOverlay = null;
    _completions = const [];
  }

  void _onHover(PointerHoverEvent event) {
    _hoverDebounce?.cancel();
    // The two overlays would otherwise visually collide; a shown completion
    // popup takes priority over starting a new hover request. Gated on the
    // overlay itself (not `_completions`, which _requestCompletions sets
    // before deciding whether to show anything).
    if (_completionOverlay != null) return;
    final renderEditable = _editableTextKey.currentState?.renderEditable;
    if (renderEditable == null) return;
    final position = renderEditable.getPositionForPoint(event.position);
    final caretRect = renderEditable.getLocalRectForCaret(position);
    final localPoint = renderEditable.globalToLocal(event.position);
    if (localPoint.dy < caretRect.top || localPoint.dy > caretRect.bottom) {
      // getPositionForPoint always snaps to the nearest character, even
      // when the pointer is well below/above any actual line (e.g. in the
      // empty space of an `expands: true` editor shorter than its pane) —
      // checking the point falls within that character's own line rules
      // that out rather than showing a tooltip anchored far from the mouse.
      _cancelHover();
      return;
    }
    _hoverDebounce = Timer(_hoverDebounceDelay, () => _requestHover(position));
  }

  void _onHoverExit(PointerExitEvent event) => _cancelHover();

  void _requestHover(TextPosition position) {
    final controller = widget.controller;
    final requestId = ++_hoverRequestId;
    controller.session.hover(position.offset).then((result) {
      if (!mounted || requestId != _hoverRequestId) return;
      // See _requestCompletions for why lastCompiledSource is the gate.
      if (controller.session.lastCompiledSource != controller.text || result.tooltip == null) {
        _hideHoverPopup();
        return;
      }
      _hoverTooltip = result.tooltip;
      _hoverPosition = position;
      _showHoverPopup();
    });
  }

  void _cancelHover() {
    _hoverDebounce?.cancel();
    _hoverDebounce = null;
    _hoverRequestId++;
    _hideHoverPopup();
  }

  void _showHoverPopup() {
    if (_hoverOverlay == null) {
      _hoverOverlay = OverlayEntry(builder: _buildHoverOverlay);
      Overlay.of(context).insert(_hoverOverlay!);
    } else {
      _hoverOverlay!.markNeedsBuild();
    }
  }

  void _hideHoverPopup() {
    _hoverOverlay?.remove();
    _hoverOverlay = null;
    _hoverTooltip = null;
    _hoverPosition = null;
  }

  Widget _buildHoverOverlay(BuildContext context) {
    final renderEditable = _editableTextKey.currentState?.renderEditable;
    final tooltip = _hoverTooltip;
    final position = _hoverPosition;
    if (renderEditable == null || tooltip == null || position == null) {
      return const SizedBox.shrink();
    }
    final caretRect = renderEditable.getLocalRectForCaret(position);
    final anchor = renderEditable.localToGlobal(caretRect.bottomLeft);
    return Positioned(
      left: anchor.dx,
      top: anchor.dy + 4,
      // Read-only content: unlike the completion popup, nothing here is
      // tappable, so it must not intercept pointer events at all — doing
      // so would fight the editor's own MouseRegion for hover/exit.
      child: IgnorePointer(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                tooltip.content,
                style: tooltip.kind == TypstTooltipKind.code ? const TextStyle(fontFamily: 'monospace') : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionOverlay(BuildContext context) {
    final renderEditable = _editableTextKey.currentState?.renderEditable;
    final selection = widget.controller.selection;
    if (renderEditable == null || !selection.isValid || _completions.isEmpty) {
      return const SizedBox.shrink();
    }
    final caretRect = renderEditable.getLocalRectForCaret(TextPosition(offset: selection.baseOffset));
    final anchor = renderEditable.localToGlobal(caretRect.bottomLeft);
    return Positioned(
      left: anchor.dx,
      top: anchor.dy + 4,
      child: TextFieldTapRegion(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 200),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _completions.length,
              itemBuilder: (context, index) {
                final item = _completions[index];
                final selected = index == _selectedCompletionIndex;
                return Material(
                  color: selected ? Theme.of(context).highlightColor : Colors.transparent,
                  child: InkWell(
                    onTap: () => _applyCompletion(item),
                    child: ListTile(
                      dense: true,
                      title: Text(item.label, overflow: TextOverflow.ellipsis, maxLines: 1),
                      // ListTile requires trailing to be a bounded-width widget — a
                      // bare Text(detail) has none, and a long detail string (a
                      // completion's one-sentence description) overflows the tile
                      // and trips ListTile's own layout assertion.
                      trailing: item.detail == null
                          ? null
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 96),
                              child: Text(
                                item.detail!,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                textAlign: TextAlign.end,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  TextSelectionControls _defaultSelectionControls() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return desktopTextSelectionControls;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return materialTextSelectionControls;
    }
  }

  @override
  Widget build(BuildContext context) {
    final focusNode = _focusNode;
    // A null color here isn't "inherit from context" — EditableText has no
    // ambient text style to fall back to, and this becomes the root of
    // TypstEditorController's whole TextSpan tree (see buildTextSpan): any
    // node the syntax theme doesn't color (plain prose, or a tag the theme
    // has no entry for) inherits it verbatim. Left null, that resolved to
    // near-white text on a light background — invisible, not merely
    // untinted. Backfilled here rather than only in the widget's own
    // default so a caller-supplied style that also omits a color doesn't
    // hit the same bug.
    final rawStyle = widget.style ?? const TextStyle(fontFamily: 'monospace', fontSize: 13);
    final style = rawStyle.color == null ? rawStyle.copyWith(color: const Color(0xFF000000)) : rawStyle;
    final cursorColor = widget.cursorColor ?? style.color ?? const Color(0xFF000000);
    final selectionColor = widget.selectionColor ?? const Color(0x664A90D9);

    // AnimatedBuilder rebuilds this whole subtree — including a fresh call
    // to buildGestureDetector — on every focus change, purely so
    // EditableText's selectionColor can be focus-gated the way TextField's
    // is. That rebuild is safe: tap-to-focus and the rebuild it triggers do
    // not fight (verified directly — see the note in
    // test/typst_code_editor_test.dart on why an earlier attempt to work
    // around a hang here turned out to be chasing a test bug, not a real
    // one, and this structure was in fact fine the whole time).
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onHover: _onHover,
      onExit: _onHoverExit,
      child: TextFieldTapRegion(
        child: AnimatedBuilder(
          animation: focusNode,
          builder: (context, _) {
            return _gestureDetectorBuilder.buildGestureDetector(
              behavior: HitTestBehavior.translucent,
              child: RepaintBoundary(
                child: EditableText(
                  key: _editableTextKey,
                  controller: widget.controller,
                  focusNode: focusNode,
                  style: style,
                  cursorColor: cursorColor,
                  backgroundCursorColor: const Color(0xFF9E9E9E),
                  // Only while focused, matching TextField: otherwise the
                  // highlight visually persists after focus moves elsewhere.
                  selectionColor: focusNode.hasFocus ? selectionColor : null,
                  selectionControls: widget.selectionControls ?? _defaultSelectionControls(),
                  maxLines: null,
                  expands: widget.expands,
                  readOnly: widget.readOnly,
                  autofocus: widget.autofocus,
                  // Typst source isn't prose: neither behavior belongs
                  // here, and this frees up the suggestion bar for our own
                  // completions (a later phase) instead of the OS's.
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onChanged: widget.onChanged,
                  scrollController: widget.scrollController,
                  scrollPhysics: widget.scrollPhysics,
                  inputFormatters: widget.inputFormatters,
                  contextMenuBuilder: widget.contextMenuBuilder,
                  // RenderEditable must not also handle pointers itself:
                  // the gesture detector above already does, via
                  // renderEditable's own selection APIs — double-handling
                  // breaks selection.
                  rendererIgnoresPointer: true,
                  // The MouseRegion above already sets the I-beam; the
                  // inner one must defer or the two fight over the cursor.
                  mouseCursor: MouseCursor.defer,
                  cursorOpacityAnimates: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
