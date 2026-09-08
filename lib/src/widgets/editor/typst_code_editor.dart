import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart'
    show AdaptiveTextSelectionToolbar, desktopTextSelectionControls, materialTextSelectionControls;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'typst_editor_controller.dart';

Widget _defaultContextMenuBuilder(BuildContext context, EditableTextState editableTextState) {
  if (SystemContextMenu.isSupportedByField(editableTextState)) {
    return SystemContextMenu.editableText(editableTextState: editableTextState);
  }
  return AdaptiveTextSelectionToolbar.editableText(editableTextState: editableTextState);
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

  @override
  void didUpdateWidget(TypstCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == null && widget.focusNode != null) {
      _internalFocusNode?.dispose();
      _internalFocusNode = null;
    }
  }

  @override
  void dispose() {
    _internalFocusNode?.dispose();
    super.dispose();
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
    final style = widget.style ?? const TextStyle(fontFamily: 'monospace', fontSize: 13);
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
