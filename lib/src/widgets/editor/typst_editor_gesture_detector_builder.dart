import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

/// A [TextSelectionGestureDetectorBuilder] that makes long-press-and-drag
/// (before releasing) extend the selection one character at a time, instead
/// of Flutter's own default of snapping to whole words on every platform
/// except iOS/macOS (see [TextSelectionGestureDetectorBuilder
/// .onSingleLongTapMoveUpdate]).
///
/// Word-wise dragging is the right default for prose, where "select more"
/// almost always means "select more words" — but Typst source is code:
/// identifiers, punctuation, and brackets don't split into words the way
/// prose does, and the same fine-grained control already available by
/// releasing and dragging a handle is more useful here from the very start
/// of the gesture.
///
/// The initial long-press still grabs the whole word under the finger — a
/// standard, expected way to start a selection — only the *drag that
/// follows, before release* changes granularity. iOS/macOS keep Flutter's
/// own behavior untouched (there, an unmodified long-press-drag already
/// moves a floating cursor character-by-character rather than snapping to
/// words, a distinct native convention this doesn't try to replace).
class TypstEditorGestureDetectorBuilder
    extends TextSelectionGestureDetectorBuilder {
  TypstEditorGestureDetectorBuilder({required super.delegate});

  // The word selected by the long-press this drag started from, captured
  // lazily on the *first* move rather than in onSingleLongTapStart: the
  // word selection Flutter's own super.onSingleLongTapStart just made
  // isn't necessarily reflected in renderEditable.selection synchronously
  // within that same call — by the first move update, at least one gesture
  // round-trip has definitely elapsed, so it's settled. Null once the drag
  // ends, or on platforms this class leaves untouched.
  TextSelection? _wordSelection;
  bool _wordSelectionCaptured = false;

  // Which edge of [_wordSelection] the drag holds fixed while the other
  // extends — decided once, from the first move's direction, and kept for
  // the rest of the drag (reset in onSingleLongTapEnd/Cancel).
  TextPosition? _fixedEdge;

  bool get _overridesGranularity =>
      defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.macOS;

  @override
  void onSingleLongTapStart(LongPressStartDetails details) {
    super.onSingleLongTapStart(details);
    _wordSelection = null;
    _wordSelectionCaptured = false;
    _fixedEdge = null;
  }

  @override
  void onSingleLongTapMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!delegate.selectionEnabled) return;
    if (!_overridesGranularity) {
      super.onSingleLongTapMoveUpdate(details);
      return;
    }
    if (!_wordSelectionCaptured) {
      _wordSelectionCaptured = true;
      _wordSelection = renderEditable.selection;
    }
    final wordSelection = _wordSelection;
    if (wordSelection == null || wordSelection.isCollapsed) {
      super.onSingleLongTapMoveUpdate(details);
      return;
    }

    final fixedEdge =
        _fixedEdge ?? _pickFixedEdge(wordSelection, details.globalPosition);
    _fixedEdge = fixedEdge;
    renderEditable.selectPositionAt(
      from: _globalPositionOf(fixedEdge),
      to: details.globalPosition,
      cause: SelectionChangedCause.longPress,
    );
    // Flutter's own default calls the private _showMagnifierIfSupportedByPlatform
    // here, which just dispatches to this same public entry point.
    editableText.showMagnifier(details.globalPosition);
  }

  @override
  void onSingleLongTapEnd(LongPressEndDetails details) {
    _wordSelection = null;
    _wordSelectionCaptured = false;
    _fixedEdge = null;
    super.onSingleLongTapEnd(details);
  }

  @override
  void onSingleLongTapCancel() {
    _wordSelection = null;
    _wordSelectionCaptured = false;
    _fixedEdge = null;
    super.onSingleLongTapCancel();
  }

  // Whichever edge of the originally-selected word is farther from where
  // the finger has dragged to stays put; the nearer edge is what the finger
  // is actually extending away from.
  TextPosition _pickFixedEdge(
    TextSelection wordSelection,
    Offset dragGlobalPosition,
  ) {
    final base = TextPosition(offset: wordSelection.baseOffset);
    final extent = TextPosition(offset: wordSelection.extentOffset);
    final baseDistance =
        (dragGlobalPosition - _globalPositionOf(base)).distanceSquared;
    final extentDistance =
        (dragGlobalPosition - _globalPositionOf(extent)).distanceSquared;
    return baseDistance >= extentDistance ? base : extent;
  }

  Offset _globalPositionOf(TextPosition position) => renderEditable
      .localToGlobal(renderEditable.getLocalRectForCaret(position).center);
}
