import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show AdaptiveTextSelectionToolbar, Material, TextMagnifier, TextSelectionToolbar, Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../document/typst_completion.dart';
import '../../document/typst_function_info.dart';
import '../../document/typst_tooltip.dart';
import 'typst_completions_builder.dart';
import 'typst_details_builder.dart';
import 'typst_editor_controller.dart';
import 'typst_editor_selection_controls.dart';
import 'typst_line_number_gutter.dart';

/// How long the mouse must rest over a token before a hover request fires.
const _hoverDebounceDelay = Duration(milliseconds: 300);

/// How long an edit must go unfollowed by another before an implicit
/// (typing-triggered) completions request fires. Short relative to
/// [_hoverDebounceDelay] — this gates a request that itself blocks on a
/// compile (see [_TypstCodeEditorState._requestCompletions]), so coalescing
/// a fast typing burst into one request matters more here than for hover,
/// which never compiles anything.
const _completionDebounceDelay = Duration(milliseconds: 150);

/// Strips `${...}` snippet placeholders from a completion's [apply] text
/// (Typst-ide's own snippet syntax — e.g. `lorem(${})`, `${lhs} + ${rhs}`,
/// or occasionally a numbered `${2:2}` tab-stop), returning the plain text
/// with every placeholder removed and the offset each one was at, in the
/// order they appeared — the caret lands on the first (or the end of the
/// text, if there were none), and Tab cycles through the rest; see
/// [_TypstCodeEditorState._snippetStops].
///
/// The content between `${` and `}` (a hint name, or a tab-stop number and
/// default) is discarded rather than kept as selected placeholder text —
/// out of scope here, since it needs its own caret/selection decision on
/// top of the tab-stop cycling this enables.
({String text, List<int> stopOffsets}) _stripSnippetPlaceholders(String apply) {
  final buffer = StringBuffer();
  final stopOffsets = <int>[];
  var i = 0;
  while (i < apply.length) {
    if (apply[i] == r'$' && i + 1 < apply.length && apply[i + 1] == '{') {
      final end = apply.indexOf('}', i + 2);
      if (end != -1) {
        stopOffsets.add(buffer.length);
        i = end + 1;
        continue;
      }
    }
    buffer.write(apply[i]);
    i++;
  }
  return (text: buffer.toString(), stopOffsets: stopOffsets);
}

/// The edit (as a common-prefix/common-suffix diff) that turned [oldText]
/// into [newText] — used to keep [_TypstCodeEditorState._snippetStops] in
/// sync as the user types inside an earlier stop, shifting later ones.
({int start, int deletedLength, int insertedLength}) _diffTextEdit(String oldText, String newText) {
  var prefix = 0;
  final minLength = oldText.length < newText.length ? oldText.length : newText.length;
  while (prefix < minLength && oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  var oldEnd = oldText.length;
  var newEnd = newText.length;
  while (oldEnd > prefix && newEnd > prefix && oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  return (start: prefix, deletedLength: oldEnd - prefix, insertedLength: newEnd - prefix);
}

/// Filters [completions] to those matching [prefix] (the text already typed
/// since the completion request's `applyFrom`), preferring an exact prefix
/// match on [TypstCompletion.label] — what the user actually sees and types
/// against, not [TypstCompletion.apply], which for a snippet can read
/// nothing like the label past its first few characters — and falling back
/// to a fuzzy (in-order, not-necessarily-contiguous) subsequence match, so
/// e.g. typing `setsty` finds `set-style`.
///
/// Prefix matches are kept ahead of fuzzy-only ones (each group keeping
/// typst-ide's own relevance order) rather than interleaved: typst-ide's
/// ranking assumes a prefix-searching caller, so the first, most-relevant
/// candidate — the one Enter/Tab applies by default — has to stay a real
/// prefix match whenever one exists, not whichever fuzzy hit happened to
/// sort first.
List<TypstCompletion> _filterCompletions(List<TypstCompletion> completions, String prefix) {
  if (prefix.isEmpty) return completions;
  final prefixLower = prefix.toLowerCase();
  final prefixMatches = <TypstCompletion>[];
  final fuzzyMatches = <TypstCompletion>[];
  for (final c in completions) {
    final labelLower = c.label.toLowerCase();
    if (labelLower.startsWith(prefixLower)) {
      prefixMatches.add(c);
    } else if (_isFuzzySubsequence(prefixLower, labelLower)) {
      fuzzyMatches.add(c);
    }
  }
  return [...prefixMatches, ...fuzzyMatches];
}

/// The start offset of every line that overlaps `[start, end)` — for
/// indent/dedent, which acts on whole lines. A collapsed selection
/// (`start == end`) is treated as touching the one line it sits on, so
/// Shift+Tab dedents the current line even with nothing selected.
///
/// A line "overlaps" if any part of it falls in `[start, end)`; in
/// particular, a selection whose end lands exactly at the start of a line
/// does *not* touch that line — nothing of it is actually selected.
List<int> _linesTouchedBy(String text, int start, int end) {
  final lineStarts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') lineStarts.add(i + 1);
  }
  if (start == end) {
    // The single line containing this position — including sitting exactly
    // at the end of the text, past every lineStart, with no trailing
    // newline to have added one more entry to lineStarts for.
    var line = 0;
    for (var i = 1; i < lineStarts.length; i++) {
      if (lineStarts[i] > start) break;
      line = i;
    }
    return [lineStarts[line]];
  }
  return [
    for (var i = 0; i < lineStarts.length; i++)
      if (start < (i + 1 < lineStarts.length ? lineStarts[i + 1] : text.length) && end > lineStarts[i])
        lineStarts[i],
  ];
}

/// How many of the (at most [max]) characters starting at [lineStart] are
/// spaces or tabs — the run a dedent would remove from that line.
int _leadingWhitespaceLength(String text, int lineStart, int max) {
  var n = 0;
  while (n < max && lineStart + n < text.length && (text[lineStart + n] == ' ' || text[lineStart + n] == '\t')) {
    n++;
  }
  return n;
}

/// The offset of the end of the line starting at [lineStart] — its `\n`'s
/// own offset, or `text.length` for the last line.
int _lineEndOffset(String text, int lineStart) {
  final idx = text.indexOf('\n', lineStart);
  return idx == -1 ? text.length : idx;
}

/// The offset of the first non-space/tab character on the line starting at
/// [lineStart] — equal to that line's own end offset for a blank line.
int _contentStartOffset(String text, int lineStart) {
  final end = _lineEndOffset(text, lineStart);
  var i = lineStart;
  while (i < end && (text[i] == ' ' || text[i] == '\t')) {
    i++;
  }
  return i;
}

/// Whether every character of [query] appears in [target], in order, though
/// not necessarily contiguously (e.g. `setsty` in `set-style`). Both must
/// already be case-normalized by the caller.
bool _isFuzzySubsequence(String query, String target) {
  var qi = 0;
  for (var ti = 0; ti < target.length && qi < query.length; ti++) {
    if (target.codeUnitAt(ti) == query.codeUnitAt(qi)) qi++;
  }
  return qi == query.length;
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
    this.magnifierConfiguration,
    this.autofocus = false,
    this.readOnly = false,
    this.expands = true,
    this.onChanged,
    this.scrollController,
    this.scrollPhysics,
    this.inputFormatters,
    this.contextMenuBuilder,
    this.completionsBuilder = defaultTypstCompletionsBuilder,
    this.detailsBuilder,
    this.showLineNumbers = true,
    this.lineNumberColor,
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

  /// Selection handles/toolbar. Defaults to [TypstEditorSelectionControls] —
  /// pdfrx-style triangle handles — on every platform, shown only for
  /// selections made by touch or stylus (never under a mouse), the same
  /// pointer-kind rule `TextField` applies. Override to get platform-native
  /// (e.g. Cupertino) handles instead, or
  /// [materialTextSelectionHandleControls] for the plain Material teardrop
  /// shape.
  ///
  /// Must be null or a `TextSelectionHandleControls`-mixin instance for
  /// [contextMenuBuilder] (and its "Toggle Comment" entry) to take effect —
  /// see `TextSelectionOverlay.showToolbar`.
  final TextSelectionControls? selectionControls;

  /// The loupe shown while dragging a selection handle or the caret on a
  /// touch device. Defaults to [typstEditorMagnifierConfiguration] — pdfrx's
  /// rounded-rect magnifier styling — rather than
  /// [TextMagnifier.adaptiveMagnifierConfiguration]. [EditableText] itself
  /// defaults to no magnifier at all, so this is set explicitly rather than
  /// left to inherit that.
  final TextMagnifierConfiguration? magnifierConfiguration;

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

  /// Builds the selection/context menu. Defaults to this widget's own
  /// (which extends the platform-adaptive default with a "Toggle Comment"
  /// entry — see [_TypstCodeEditorState._buildDefaultContextMenu]);
  /// override to replace it entirely.
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  /// Builds the completion popup's contents (everything inside its
  /// position/dismissal chrome, which this widget keeps ownership of — see
  /// [TypstCompletionsBuilder]). Defaults to [defaultTypstCompletionsBuilder];
  /// override to restyle the popup without forking this widget.
  final TypstCompletionsBuilder completionsBuilder;

  /// Builds an IntelliSense-style details panel — full signature,
  /// description, and example code — shown next to the completion popup for
  /// whichever item is currently selected, when it resolves to a function.
  /// Null (the default) shows no panel at all; pass
  /// [defaultTypstDetailsBuilder] for a ready-made look, or a custom
  /// [TypstDetailsBuilder] to restyle it.
  final TypstDetailsBuilder? detailsBuilder;

  /// Shows a line-number gutter to the left of the source text, scroll-
  /// synced with the editor. See [TypstLineNumberGutter].
  final bool showLineNumbers;

  /// Line-number color, when [showLineNumbers] is true. Defaults to
  /// [style]'s color at 40% opacity.
  final Color? lineNumberColor;

  @override
  State<TypstCodeEditor> createState() => _TypstCodeEditorState();
}

class _TypstCodeEditorState extends State<TypstCodeEditor> implements TextSelectionGestureDetectorBuilderDelegate {
  final GlobalKey<EditableTextState> _editableTextKey = GlobalKey<EditableTextState>();
  late final _gestureDetectorBuilder = TextSelectionGestureDetectorBuilder(delegate: this);

  // What `TextField` works out as its own `_showSelectionHandles` and passes
  // down: `EditableText.showSelectionHandles` defaults to false, and without
  // it handles are built but held at zero opacity on every platform. A
  // notifier rather than a plain bool so the default controls can also
  // make hidden handles ignore pointers — see
  // TypstEditorSelectionControls.handlesVisible.
  final _showSelectionHandles = ValueNotifier<bool>(false);

  // One instance for this state's lifetime: EditableText tears down and
  // recreates its whole selection overlay whenever `selectionControls`
  // changes identity (see its didUpdateWidget), which a fresh instance per
  // build would trigger on every rebuild — mid-drag included.
  //
  // Used on desktop platforms too: a touchscreen laptop needs visible
  // handles as much as a tablet, and the platform's own desktop controls
  // draw none at all. Mouse selections still get none — see
  // _shouldShowSelectionHandles. Being a `TextSelectionHandleControls`
  // also keeps [contextMenuBuilder] (and "Toggle Comment") in effect: see
  // `TextSelectionOverlay.showToolbar`.
  late final TextSelectionControls _typstSelectionControls = TypstEditorSelectionControls(
    handlesVisible: _showSelectionHandles,
  );

  FocusNode? _internalFocusNode;
  FocusNode get _focusNode => widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  // `EditableText` creates its own internal `ScrollController` when none is
  // supplied, which the line-number gutter (a separate widget entirely,
  // syncing purely off a `ScrollController`'s offset) has no way to reach.
  // An explicit one is always passed to `EditableText` below instead, so
  // the gutter always has a real controller to listen to, same pattern as
  // `_focusNode` above.
  ScrollController? _internalScrollController;
  ScrollController get _scrollController =>
      widget.scrollController ?? (_internalScrollController ??= ScrollController());

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
  Timer? _completionDebounce;
  String? _lastControllerText;
  TextSelection? _lastControllerSelection;
  FocusNode? _keyHandlerNode;
  FocusOnKeyEventCallback? _previousOnKeyEvent;

  // Set for the duration of this widget's own programmatic
  // `controller.value =` assignments (applying a completion, indenting/
  // dedenting), so _onControllerChanged's synchronous notification from
  // that assignment doesn't dispatch a fresh completions request for
  // wherever it happened to land the caret — most visibly, Tab landing on a
  // blank indented line, where an empty typed prefix would otherwise match
  // every completion and pop a full, unfiltered list right after the
  // keystroke that was supposed to just indent.
  bool _applyingProgrammaticEdit = false;

  // Absolute offsets (in the *current* text — see _onControllerChanged's
  // diff-adjustment) of every stop in a just-applied snippet, in order —
  // including the first, which is where the caret already sits right after
  // applying. Only set (to more than one entry) when a completion's `apply`
  // had more than one `${...}` placeholder; empty means no active tab-stop
  // session, which is the overwhelmingly common case (most completions have
  // at most one stop) and also what most non-Tab navigation lazily resets
  // it to — see _tryAdvanceSnippetStop.
  List<int> _snippetStops = const [];

  // --- completion details panel ---
  TypstFunctionInfo? _details;
  int _detailsRequestId = 0;

  // True when the popup is showing *only* `_details` — no completion list —
  // because typst-ide itself offered nothing to complete at this position
  // (as opposed to our own prefix/fuzzy filter narrowing a real list down
  // to nothing). The clearest case: the cursor sits inside a call to a
  // function whose only parameter is a variadic sink (`f(..options)`,
  // common for "flexible options dictionary" APIs like cetz's
  // `set-style`) — Typst has no declared parameter names to offer there at
  // all, so completions comes back genuinely empty, and a bare silent
  // popup-that-never-appears is worse than at least showing what the
  // function itself is — see _requestFallbackDetails.
  bool _fallbackDetailsOnly = false;

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
      _completionDebounce?.cancel();
      _hideCompletionPopup();
      _cancelHover();
      _snippetStops = const []; // offsets refer to the old controller's text
    }
    if (oldWidget.focusNode == null && widget.focusNode != null) {
      _internalFocusNode?.dispose();
      _internalFocusNode = null;
    }
    if (oldWidget.scrollController == null && widget.scrollController != null) {
      _internalScrollController?.dispose();
      _internalScrollController = null;
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
    _completionDebounce?.cancel();
    _completionOverlay?.remove();
    _hoverDebounce?.cancel();
    _hoverOverlay?.remove();
    _internalFocusNode?.dispose();
    _internalScrollController?.dispose();
    _showSelectionHandles.dispose();
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
      // Checked ahead of the completions popup below: typing inside a
      // snippet stop (filling in a condition, a name, ...) routinely
      // retriggers an *implicit* completions popup of its own — offering,
      // say, a trivial match for whatever was just typed. Without this
      // ordering, that popup's own Tab-applies-the-highlighted-item
      // handling would win by running first, silently no-op-applying it
      // and (since it isn't itself a multi-stop snippet) wiping the
      // snippet session — instead of advancing to the next stop, which is
      // what Tab means while one is active regardless of what else is
      // incidentally showing. Traversal resolves on key-down, so handling
      // only that — not the matching key-up — is enough to keep focus from
      // moving to the next widget.
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab && _snippetStops.isNotEmpty) {
        if (_tryAdvanceSnippetStop()) {
          _hideCompletionPopup();
          return KeyEventResult.handled;
        }
      }
      if (_completions.isNotEmpty) {
        // Shift+Tab shares LogicalKeyboardKey.tab with plain Tab, but
        // "confirm the highlighted item" is not a sensible meaning for it
        // in any editor's completion popup — treated like Escape instead,
        // rather than falling into the `case tab:` below and silently
        // applying a completion the user pressed Shift for.
        if (event.logicalKey == LogicalKeyboardKey.tab && HardwareKeyboard.instance.isShiftPressed) {
          _hideCompletionPopup();
          return KeyEventResult.handled;
        }
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
      // A fallback-details-only popup (see _fallbackDetailsOnly) has no
      // items to navigate/apply, so it doesn't hit the switch above at
      // all (`_completions` stays empty for it) — only Escape applies.
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape && _fallbackDetailsOnly) {
        _hideCompletionPopup();
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.space &&
          HardwareKeyboard.instance.isControlPressed) {
        _requestCompletions(explicit: true);
        return KeyEventResult.handled;
      }
      // Reached only with no snippet session and no completions popup open
      // (both handled, and returned, above) — plain editor-indentation Tab/
      // Shift+Tab. A collapsed selection just gets/loses one indent unit at
      // the caret; a real selection indents/dedents every line it touches,
      // keeping the same text selected afterward (shifted by however much
      // was inserted/removed) so a second Tab press keeps working.
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          _dedentSelection();
        } else {
          _indentSelection();
        }
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.slash &&
          HardwareKeyboard.instance.isControlPressed) {
        _toggleLineComments();
        return KeyEventResult.handled;
      }
    }
    return _previousOnKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
  }

  void _indentSelection() {
    final controller = widget.controller;
    final selection = controller.selection;
    if (!selection.isValid) return;
    final unit = controller.indentUnit;
    if (selection.isCollapsed) {
      // No selection: Tab just inserts the indent unit at the caret,
      // wherever it sits in the line — not line-start-anchored, unlike the
      // multi-line case below.
      final offset = selection.baseOffset;
      final text = controller.text;
      _applyingProgrammaticEdit = true;
      controller.value = TextEditingValue(
        text: text.replaceRange(offset, offset, unit),
        selection: TextSelection.collapsed(offset: offset + unit.length),
      );
      _applyingProgrammaticEdit = false;
      return;
    }
    final text = controller.text;
    final start = selection.start;
    final end = selection.end;
    final lineStarts = _linesTouchedBy(text, start, end);
    final buffer = StringBuffer();
    var cursor = 0;
    for (final lineStart in lineStarts) {
      buffer
        ..write(text.substring(cursor, lineStart))
        ..write(unit);
      cursor = lineStart;
    }
    buffer.write(text.substring(cursor));
    // An insertion landing exactly at the selection's own start offset
    // stays *outside* it (the selection still begins where it did,
    // logically — right before whatever's now there); the same insertion
    // point relative to the *end* offset is included (the selection grows
    // to cover newly-inserted content up to and including its own edge).
    // Only matters when a selection edge sits exactly at a line's start —
    // this codebase's own indent test never hits that (its selection
    // starts mid-line) but the exact same code toggling a comment on a
    // selection starting at column 0 does, and got this wrong before the
    // asymmetry was added here.
    int mapOffset(int x, {required bool isEnd}) {
      final touching = isEnd ? lineStarts.where((ls) => ls <= x) : lineStarts.where((ls) => ls < x);
      return x + unit.length * touching.length;
    }

    _applyingProgrammaticEdit = true;
    controller.value = TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection(baseOffset: mapOffset(start, isEnd: false), extentOffset: mapOffset(end, isEnd: true)),
    );
    _applyingProgrammaticEdit = false;
  }

  void _dedentSelection() {
    final controller = widget.controller;
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) return;
    final unit = controller.indentUnit;
    final start = selection.start;
    final end = selection.end;
    final lineStarts = _linesTouchedBy(text, start, end);
    // How many leading whitespace characters to strip from each touched
    // line — up to one indent unit's worth, but never more than the line
    // actually has (so a line indented by only one space, say, still loses
    // just that one space instead of eating into its content).
    final removed = <int, int>{
      for (final lineStart in lineStarts) lineStart: _leadingWhitespaceLength(text, lineStart, unit.length),
    };
    if (removed.values.every((n) => n == 0)) return; // nothing to remove
    final buffer = StringBuffer();
    var cursor = 0;
    for (final lineStart in lineStarts) {
      buffer.write(text.substring(cursor, lineStart));
      cursor = lineStart + removed[lineStart]!;
    }
    buffer.write(text.substring(cursor));
    int mapOffset(int x) {
      var delta = 0;
      for (final lineStart in lineStarts) {
        if (lineStart >= x) break;
        delta += (x - lineStart).clamp(0, removed[lineStart]!);
      }
      return x - delta;
    }

    _applyingProgrammaticEdit = true;
    controller.value = TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection(baseOffset: mapOffset(start), extentOffset: mapOffset(end)),
    );
    _applyingProgrammaticEdit = false;
  }

  // Toggles Typst's `//` line comment on every line the selection touches
  // (or just the current line, for a collapsed caret) — Ctrl+/, and the
  // context menu's "Toggle Comment" entry. Whether this comments or
  // uncomments is decided for the whole touched range at once: if every
  // non-blank touched line is already commented, all of them (blank lines
  // included, if they happen to carry a comment marker too) get
  // uncommented; otherwise every line missing one gets commented — the
  // same "all or nothing" rule most editors use, so toggling twice in a
  // row is a no-op rather than commenting some lines and uncommenting
  // others depending on their prior state.
  //
  // The marker is inserted/removed right after each line's own leading
  // whitespace (not at column 0), so it lines up with that line's code
  // instead of the selection's left edge.
  void _toggleLineComments() {
    final controller = widget.controller;
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) return;
    final start = selection.start;
    final end = selection.end;
    final lineStarts = _linesTouchedBy(text, start, end);
    final contentStarts = {for (final ls in lineStarts) ls: _contentStartOffset(text, ls)};
    final nonBlank = lineStarts.where((ls) => contentStarts[ls]! < _lineEndOffset(text, ls)).toList();
    final allCommented = nonBlank.isNotEmpty && nonBlank.every((ls) => text.startsWith('//', contentStarts[ls]!));

    const marker = '// ';
    final buffer = StringBuffer();
    var cursor = 0;
    // How many characters were removed (uncommenting) at each line's
    // content-start position — 0 for a line the toggle doesn't touch (e.g.
    // a blank line while commenting, or an already-uncommented line while
    // uncommenting a mixed selection is not possible since allCommented
    // requires every non-blank line to already match).
    final removedAt = <int, int>{};
    for (final ls in lineStarts) {
      final cs = contentStarts[ls]!;
      buffer.write(text.substring(cursor, cs));
      if (allCommented) {
        if (text.startsWith('//', cs)) {
          final removeLen = (cs + 2 < text.length && text[cs + 2] == ' ') ? 3 : 2;
          removedAt[ls] = removeLen;
          cursor = cs + removeLen;
        } else {
          cursor = cs;
        }
      } else if (cs < _lineEndOffset(text, ls)) {
        buffer.write(marker);
        cursor = cs;
      } else {
        cursor = cs; // blank line: leave it alone rather than adding a bare "// "
      }
    }
    buffer.write(text.substring(cursor));

    // See _indentSelection's mapOffset for why inserting the marker exactly
    // at a selection edge is biased differently for that edge's start vs.
    // end (only relevant when commenting, not uncommenting — the clamp in
    // the removal branch below is already symmetric, since "0 characters
    // removed before this exact point" is correct whichever edge it is).
    int mapOffset(int x, {required bool isEnd}) {
      var delta = 0;
      for (final ls in lineStarts) {
        final cs = contentStarts[ls]!;
        if (allCommented) {
          if (cs > x) break;
          final removed = removedAt[ls];
          if (removed != null) delta -= (x - cs).clamp(0, removed);
        } else {
          if (isEnd ? cs > x : cs >= x) break;
          if (cs < _lineEndOffset(text, ls)) delta += marker.length;
        }
      }
      return x + delta;
    }

    _applyingProgrammaticEdit = true;
    controller.value = TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection(baseOffset: mapOffset(start, isEnd: false), extentOffset: mapOffset(end, isEnd: true)),
    );
    _applyingProgrammaticEdit = false;
  }

  // Finds the next stop *after the caret* rather than tracking "which stop
  // index are we on": the user can type arbitrarily much at the current
  // stop (the whole point of it) before pressing Tab again, so matching an
  // exact remembered offset would already be stale by the time Tab lands —
  // e.g. applying `if-else`'s `#if ${} { ${} } else { ${} }`, typing a
  // condition at the first stop, then pressing Tab. A caret outside the
  // whole span is treated the same as no session: the user navigated away
  // by some other means (click, arrow keys), so Tab reverting to normal
  // focus traversal is the least surprising thing to do.
  bool _tryAdvanceSnippetStop() {
    final selection = widget.controller.selection;
    if (!selection.isCollapsed) {
      _snippetStops = const [];
      return false;
    }
    final cursor = selection.baseOffset;
    if (cursor < _snippetStops.first || cursor > _snippetStops.last) {
      _snippetStops = const [];
      return false;
    }
    for (final stop in _snippetStops) {
      if (stop > cursor) {
        widget.controller.selection = TextSelection.collapsed(offset: stop);
        return true;
      }
    }
    // Already at (or past) the last stop — this Tab ends the session and
    // falls through to normal behavior instead.
    _snippetStops = const [];
    return false;
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    final text = controller.text;
    final selection = controller.selection;
    final textChanged = text != _lastControllerText;
    final selectionChanged = selection != _lastControllerSelection;
    if (textChanged && _snippetStops.isNotEmpty && _lastControllerText != null) {
      // Keep remaining stops accurate as the user types inside an earlier
      // one — e.g. typing a 3-character condition at the first `if` stop
      // must push the body's `{ }` stop 3 characters later, or Tab would
      // land short/long of it.
      final edit = _diffTextEdit(_lastControllerText!, text);
      final delta = edit.insertedLength - edit.deletedLength;
      final editEnd = edit.start + edit.deletedLength;
      _snippetStops = [
        for (final stop in _snippetStops)
          stop <= edit.start
              ? stop
              : (stop <= editEnd ? edit.start + edit.insertedLength : stop + delta),
      ];
    }
    _lastControllerText = text;
    _lastControllerSelection = selection;
    // Any real text or caret change means whatever was under the mouse
    // when the tooltip was requested is no longer what the tooltip
    // describes — independent of the completion-popup logic below.
    if (textChanged || selectionChanged) _cancelHover();
    if (_applyingProgrammaticEdit) {
      // Tracking above stays accurate either way; just skip reacting to a
      // change this widget made itself (see the field's doc comment).
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
    _scheduleCompletions();
  }

  // Debounced entry point for a typing-triggered request — see
  // _completionDebounceDelay's doc comment for why this needs its own
  // (short) debounce rather than firing on every keystroke directly.
  // Ctrl+Space's explicit trigger calls _requestCompletions directly,
  // bypassing this: an explicit ask should be immediate.
  void _scheduleCompletions() {
    _completionDebounce?.cancel();
    _completionDebounce = Timer(_completionDebounceDelay, () => _requestCompletions(explicit: false));
  }

  void _requestCompletions({required bool explicit}) {
    _completionDebounce?.cancel();
    final controller = widget.controller;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _hideCompletionPopup();
      return;
    }
    final cursor = selection.baseOffset;
    final text = controller.text;
    final requestId = ++_completionRequestId;
    _runCompletionsRequest(requestId: requestId, text: text, cursor: cursor, explicit: explicit);
  }

  // completions() itself resolves in single-digit milliseconds, but
  // typst-ide's analysis reads the World's own registered Source, which
  // only updates when something calls TypstSession.compile — normally a
  // host app's own page-render compile, debounced (deliberately: to avoid
  // recompiling a whole document on every keystroke) far more coarsely
  // than completions need. Comparing against whatever that debounce last
  // landed meant a request dispatched by typing was always checked against
  // a World that hadn't caught up to the very edit that triggered it — so
  // it never once passed. Compiling directly here, only when the World
  // doesn't already match, decouples completions from that cycle (and from
  // whether a host wires up page rendering via updateSource at all).
  Future<void> _runCompletionsRequest({
    required int requestId,
    required String text,
    required int cursor,
    required bool explicit,
  }) async {
    final controller = widget.controller;
    if (controller.session.lastCompiledSource != text) {
      await controller.session.compile(text);
      if (!mounted || requestId != _completionRequestId) return;
    }
    final result = await controller.session.completions(cursor, explicit: explicit);
    if (!mounted || requestId != _completionRequestId) return;
    // Still guards the buffer or cursor having moved on while the above was
    // in flight — the compile above can take a while on a large document,
    // and typing doesn't wait for it.
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
    final filtered = _filterCompletions(result.completions, prefix);
    _completions = filtered;
    _completionApplyFrom = result.applyFromUtf16;
    _selectedCompletionIndex = 0;
    if (filtered.isEmpty) {
      _hideCompletionPopup();
      // Only when typst-ide itself offered nothing (not when our own
      // prefix/fuzzy filter is what narrowed a real list down to empty) —
      // otherwise this would show function details while the user is
      // simply mid-typing a param name that doesn't match anything yet.
      if (result.completions.isEmpty) _requestFallbackDetails(cursor);
    } else {
      _showCompletionPopup();
      _requestDetails();
    }
  }

  // Falls back to showing the enclosing function's own signature/docs (via
  // `detailsBuilder`, when the caller opted in) when typst-ide's own
  // completions came back completely empty — see `_fallbackDetailsOnly`'s
  // doc comment for why. A no-op if nothing resolves at `cursor` (e.g. it's
  // not actually inside any call) or the caller never opted into a
  // `detailsBuilder` at all.
  void _requestFallbackDetails(int cursor) {
    final builder = widget.detailsBuilder;
    if (builder == null) return;
    final controller = widget.controller;
    final requestId = ++_detailsRequestId;
    // The label only matters for the "browsing an unfinished identifier"
    // fallback inside functionInfo — irrelevant here, since there's no
    // completion item to name; cursor-context resolution is the only path
    // that can possibly apply.
    controller.session.functionInfo(cursor, '').then((result) {
      if (!mounted || requestId != _detailsRequestId) return;
      final stillFresh =
          controller.session.lastCompiledSource == controller.text &&
          controller.selection.isCollapsed &&
          controller.selection.baseOffset == cursor;
      if (!stillFresh || result.info == null) return;
      _details = result.info;
      _fallbackDetailsOnly = true;
      _showCompletionPopup();
    });
  }

  void _moveCompletionSelection(int delta) {
    if (_completions.isEmpty) return;
    final count = _completions.length;
    _selectedCompletionIndex = (_selectedCompletionIndex + delta) % count;
    if (_selectedCompletionIndex < 0) _selectedCompletionIndex += count;
    _completionOverlay?.markNeedsBuild();
    _requestDetails();
  }

  // Fetches details for whatever's now selected, for the details panel — a
  // no-op unless a caller opted in via `detailsBuilder`. `_detailsRequestId`
  // guards against the classic race also handled for completions/hover: the
  // user can arrow through several items faster than each fetch resolves,
  // and only the *last* selection's result should ever land.
  void _requestDetails() {
    _details = null;
    final builder = widget.detailsBuilder;
    if (builder == null || _completions.isEmpty) {
      ++_detailsRequestId; // invalidate any fetch already in flight
      return;
    }
    final item = _completions[_selectedCompletionIndex];
    if (item.kind.tag != TypstCompletionKindTag.func) {
      ++_detailsRequestId;
      _completionOverlay?.markNeedsBuild();
      return;
    }
    final controller = widget.controller;
    final cursor = controller.selection.baseOffset;
    final requestId = ++_detailsRequestId;
    controller.session.functionInfo(cursor, item.label).then((result) {
      // Also covers the popup having been dismissed while this was in
      // flight — `_hideCompletionPopup` bumps `_detailsRequestId` too, so a
      // stale response can't reopen/repaint an overlay that's gone.
      if (!mounted || requestId != _detailsRequestId) return;
      _details = result.info;
      _completionOverlay?.markNeedsBuild();
    });
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
    final firstStop = stripped.stopOffsets.isEmpty ? stripped.text.length : stripped.stopOffsets.first;
    _applyingProgrammaticEdit = true;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: _completionApplyFrom + firstStop),
    );
    _applyingProgrammaticEdit = false;
    _hideCompletionPopup();
    _snippetStops = stripped.stopOffsets.length > 1
        ? [for (final offset in stripped.stopOffsets) _completionApplyFrom + offset]
        : const [];
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
    _details = null;
    _fallbackDetailsOnly = false;
    ++_detailsRequestId; // invalidate any in-flight functionInfo fetch
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

  // Margin kept clear between the popup and the window edge it's closest
  // to, in both the flip decision and the height clamp below.
  static const _popupEdgeMargin = 8.0;

  Widget _buildCompletionOverlay(BuildContext context) {
    final renderEditable = _editableTextKey.currentState?.renderEditable;
    final selection = widget.controller.selection;
    final hasList = _completions.isNotEmpty;
    if (renderEditable == null || !selection.isValid || (!hasList && !_fallbackDetailsOnly)) {
      return const SizedBox.shrink();
    }
    final caretRect = renderEditable.getLocalRectForCaret(TextPosition(offset: selection.baseOffset));
    final caretBottom = renderEditable.localToGlobal(caretRect.bottomLeft);
    final caretTop = renderEditable.localToGlobal(caretRect.topLeft);
    final detailsBuilder = widget.detailsBuilder;
    final details = _details;
    final list = hasList
        ? widget.completionsBuilder(context, _completions, _selectedCompletionIndex, _applyCompletion)
        : null;
    // Opens downward (the common case) unless there's genuinely more room
    // above the caret than below it — favoring below on a tie, since that's
    // where a user's eyes already are while typing. Without this, a popup
    // near the bottom of a short window renders past the window's edge and
    // gets hard-clipped by the Overlay's own Stack, cropping whichever rows
    // (or the details panel entirely) didn't fit — not scrolled, just gone.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final spaceBelow = screenHeight - caretBottom.dy - _popupEdgeMargin;
    final spaceAbove = caretTop.dy - _popupEdgeMargin;
    final opensBelow = spaceBelow >= spaceAbove;
    final content = TextFieldTapRegion(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: _popupMaxHeight(context, caretTop.dy, caretBottom.dy)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          // Both panels line up on the edge facing the caret: a details panel
          // taller than the list beside it would otherwise leave the list
          // floating away from the line whenever the popup opens above it.
          crossAxisAlignment: opensBelow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            ?list,
            if (detailsBuilder != null && details != null) ...[
              if (list != null) const SizedBox(width: 8),
              detailsBuilder(context, details),
            ],
          ],
        ),
      ),
    );
    return Positioned(
      left: caretBottom.dx,
      top: opensBelow ? caretBottom.dy + 4 : null,
      bottom: opensBelow ? null : screenHeight - caretTop.dy + 4,
      child: content,
    );
  }

  // The most vertical space either above or below the caret can offer,
  // clamped so a popup taller than the window still fits: content past this
  // scrolls internally (both the default completions list and details
  // builder already do; a custom builder that doesn't will just render
  // however tall it wants, the same as before this existed).
  double _popupMaxHeight(BuildContext context, double caretTopY, double caretBottomY) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final spaceBelow = screenHeight - caretBottomY - _popupEdgeMargin;
    final spaceAbove = caretTopY - _popupEdgeMargin;
    final available = spaceBelow >= spaceAbove ? spaceBelow : spaceAbove;
    return available < 0 ? 0 : available;
  }

  /// The selection/context menu shown by default — the platform-adaptive
  /// [AdaptiveTextSelectionToolbar], with a "Toggle Comment" entry prepended
  /// (see [_toggleLineComments]).
  ///
  /// [SystemContextMenu] (the OS-drawn menu, used on platforms that support
  /// it) is opaque and can't carry custom entries at all — falls back to
  /// the plain, unmodified system menu there, same as before this existed.
  Widget _buildDefaultContextMenu(BuildContext context, EditableTextState editableTextState) {
    if (SystemContextMenu.isSupportedByField(editableTextState)) {
      return SystemContextMenu.editableText(editableTextState: editableTextState);
    }
    final buttonItems = [
      ContextMenuButtonItem(
        onPressed: () {
          _toggleLineComments();
          editableTextState.hideToolbar();
        },
        label: 'Toggle Comment',
      ),
      ...editableTextState.contextMenuButtonItems,
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: _anchorsClearOfHandles(context, editableTextState.contextMenuAnchors),
      buttonItems: buttonItems,
    );
  }

  // The platform toolbars only keep clear of the platform's own handles,
  // not these taller triangle flags — one above the selection's start, one
  // below its end. Left alone, Material's toolbar sits 8px above the
  // selection, over the start flag (or, flipped below for lack of room,
  // over the end flag), and a desktop menu — opened by a touch long-press
  // on a touchscreen laptop — puts its top-left corner on the selection
  // itself, over the end flag and half the selected text. Moves each anchor
  // past the flag on its side. Left alone when no handles show (a mouse
  // selection) or for caller-supplied controls, whose handles are unknown.
  TextSelectionToolbarAnchors _anchorsClearOfHandles(BuildContext context, TextSelectionToolbarAnchors anchors) {
    if (!_showSelectionHandles.value || widget.selectionControls != null) return anchors;
    final collapsed = widget.controller.selection.isCollapsed;
    final above = collapsed ? 0.0 : TypstEditorSelectionControls.handleSize;
    final below = collapsed ? TypstEditorSelectionControls.collapsedDiameter : TypstEditorSelectionControls.handleSize;
    const gap = 8.0;
    final secondary = anchors.secondaryAnchor ?? anchors.primaryAnchor;
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        // TextSelectionToolbar: 8px above the primary anchor, or
        // kToolbarContentDistanceBelow under the secondary one.
        return TextSelectionToolbarAnchors(
          primaryAnchor: anchors.primaryAnchor - Offset(0, above),
          secondaryAnchor:
              secondary + Offset(0, math.max(0, below + gap - TextSelectionToolbar.kToolbarContentDistanceBelow)),
        );
      case TargetPlatform.iOS:
        // CupertinoTextSelectionToolbar: a fixed distance off either anchor.
        return TextSelectionToolbarAnchors(
          primaryAnchor: anchors.primaryAnchor - Offset(0, above),
          secondaryAnchor: secondary + Offset(0, below),
        );
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
        // A dropdown menu, top-left corner on its one anchor.
        return TextSelectionToolbarAnchors(primaryAnchor: secondary + Offset(0, below + gap));
    }
  }

  // Mirrors TextField's own `_shouldShowSelectionHandles`: handles only for
  // a selection made by touch or stylus (the gesture detector builder
  // records the pointer kind of the gesture behind it), never for keyboard
  // edits, and never for a bare caret in a read-only editor.
  bool _shouldShowSelectionHandles(SelectionChangedCause? cause) {
    if (!_gestureDetectorBuilder.shouldShowSelectionToolbar || !_gestureDetectorBuilder.shouldShowSelectionHandles) {
      return false;
    }
    if (cause == SelectionChangedCause.keyboard) return false;
    if (widget.readOnly && widget.controller.selection.isCollapsed) return false;
    if (cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.stylusHandwriting) {
      return true;
    }
    return widget.controller.text.isNotEmpty;
  }

  void _handleSelectionChanged(TextSelection selection, SelectionChangedCause? cause) {
    final show = _shouldShowSelectionHandles(cause);
    if (show != _showSelectionHandles.value) {
      setState(() {
        _showSelectionHandles.value = show;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final focusNode = _focusNode;
    final scrollController = _scrollController;
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
    final editor = MouseRegion(
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
                  selectionControls: widget.selectionControls ?? _typstSelectionControls,
                  showSelectionHandles: _showSelectionHandles.value,
                  onSelectionChanged: _handleSelectionChanged,
                  magnifierConfiguration:
                      widget.magnifierConfiguration ?? typstEditorMagnifierConfiguration,
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
                  scrollController: scrollController,
                  scrollPhysics: widget.scrollPhysics,
                  inputFormatters: widget.inputFormatters,
                  contextMenuBuilder: widget.contextMenuBuilder ?? _buildDefaultContextMenu,
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

    if (!widget.showLineNumbers) return editor;

    final lineCount = '\n'.allMatches(widget.controller.text).length + 1;
    final gutterColor = widget.lineNumberColor ?? (style.color ?? const Color(0xFF000000)).withValues(alpha: 0.4);
    return LayoutBuilder(
      builder: (context, constraints) {
        // `CrossAxisAlignment.stretch` needs a bounded height to stretch
        // into; without one (e.g. this editor placed directly in a `Column`
        // with no `Expanded`/sized ancestor — an unusual embedding, but a
        // legal one, since `expands` defaults to true and normally supplies
        // its own bounded-height contract) it forces infinite constraints
        // on the Row's children and crashes. Falling back to no gutter
        // there is a graceful degradation, not a real loss: there's no
        // well-defined "full height" to draw a gutter against anyway.
        if (!constraints.hasBoundedHeight) return editor;
        final gutterWidth = typstLineNumberGutterWidth(style, lineCount);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TypstLineNumberGutter(
              text: widget.controller.text,
              style: style,
              scrollController: scrollController,
              textWidth: (constraints.maxWidth - gutterWidth).clamp(0, double.infinity),
              width: gutterWidth,
              color: gutterColor,
            ),
            Expanded(child: editor),
          ],
        );
      },
    );
  }
}
