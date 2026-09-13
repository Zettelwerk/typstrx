part of 'typst_viewer.dart';

// Touch selection handles: a pdfrx-faithful port — a solid 30x30 right
// triangle ("flag") rather than a circle+stem, same size, same two LTR
// orientations, same alpha/shadow-by-state table. See
// _TriangleHandlePainter and _HandleState below.
const _handleSize = 30.0;

// The magnifier's own size and how far above the touch point it floats.
// pdfrx's own magnifier is a wide horizontal strip, not a small square
// loupe — its content rect spans +-2x the character's height horizontally
// but only +-0.2x vertically (see _getMagnifierRect), then scales so the
// *shorter* side lands on 80px, leaving the wider side considerably larger
// — a single fixed-aspect size here rather than that per-character
// computation, but picked to land in the same "wide strip" territory. The
// decoration (rounded rect, radius, shadow) mirrors pdfrx's
// _buildMagnifierDecoration exactly; only the sourcing technique differs —
// pdfrx re-renders the page at high resolution into a dedicated cache,
// this uses RawMagnifier's backdrop-filter sampling of whatever's already
// painted below it, which avoids adding a second render/cache path for a
// feature that's already showing rasterized tiles (re-rendering wouldn't
// gain resolution beyond the current tile, only cost more).
const _magnifierSize = Size(160, 48);
// ~1cm above the finger: touch devices report logical pixels at roughly
// 160/inch (Android's dp baseline; iOS points land close to the same),
// so 1cm ≈ 160 / 2.54 ≈ 63 logical px. Flutter has no exact physical-size
// query, so this is an approximation, not a precise measurement — but
// good enough to keep the magnifier clear of the fingertip instead of
// nearly touching it (the previous 26px left its bottom edge ~2px above
// the touch point).
const _magnifierAboveFocalPoint = 63.0;
const _magnifierScale = 1.5;
const _magnifierBorderRadius = 30.0;

/// A selection handle's visual state — mirrors pdfrx's
/// `PdfViewerTextSelectionAnchorHandleState`. Only `normal`/`dragging` are
/// reachable here (no mouse-hover concept for a touch-only overlay).
enum _HandleState { normal, dragging }

/// The two pdfrx LTR handle shapes: a solid 30x30 right triangle, its right
/// angle at the corner that anchors to the selection's text edge — bottom-
/// right for the start handle, top-left for the end handle. Both share the
/// same hypotenuse orientation, top-right to bottom-left.
Path _startHandlePath() => Path()
  ..moveTo(30, 0)
  ..lineTo(30, 30)
  ..lineTo(0, 30)
  ..close();

Path _endHandlePath() => Path()
  ..moveTo(0, 0)
  ..lineTo(30, 0)
  ..lineTo(0, 30)
  ..close();

/// Paints one triangle handle — a direct port of pdfrx's `_buildHandle`:
/// a drop shadow (state-gated) under a flat fill, alpha/shadow chosen by
/// [state].
class _TriangleHandlePainter extends CustomPainter {
  _TriangleHandlePainter({
    required this.path,
    required this.color,
    required this.state,
  });

  final Path path;
  final Color color;
  final _HandleState state;

  @override
  void paint(Canvas canvas, Size size) {
    final (alpha, shadow) = switch (state) {
      _HandleState.normal => (0.7, true),
      _HandleState.dragging => (1.0, false),
    };
    if (shadow) canvas.drawShadow(path, Colors.black, 4, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(covariant _TriangleHandlePainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.state != state;
}

/// A position in the document's text: a character on a page.
class _SelPoint implements Comparable<_SelPoint> {
  const _SelPoint(this.pageIndex, this.charIndex);

  final int pageIndex;
  final int charIndex;

  @override
  int compareTo(_SelPoint other) => pageIndex != other.pageIndex
      ? pageIndex - other.pageIndex
      : charIndex - other.charIndex;

  @override
  bool operator ==(Object other) =>
      other is _SelPoint &&
      other.pageIndex == pageIndex &&
      other.charIndex == charIndex;

  @override
  int get hashCode => Object.hash(pageIndex, charIndex);
}

/// Text selection, link handling, and clipboard support for
/// [_TypstViewerState]. Lives in an extension so the gesture/paint logic
/// stays out of the main widget file; state fields are on the state class.
extension _TypstViewerSelection on _TypstViewerState {
  // ---- lazy text/link loading ----

  /// Preloads text and link geometry for the given pages (invoked after the
  /// render pass; the data is small compared to page images).
  Future<void> _preloadPageText(TypstDocument document, Set<int> pages) async {
    if (!widget.params.enableTextSelection) return;
    for (final pageNumber in pages) {
      if (_pageTexts.containsKey(pageNumber) ||
          _loadingPageText.contains(pageNumber)) {
        continue;
      }
      _loadingPageText.add(pageNumber);
      try {
        final page = document.pages[pageNumber - 1];
        final text = await page.loadStructuredText();
        final links = await page.loadLinks();
        if (!mounted || _document != document) return;
        if (text != null) _pageTexts[pageNumber] = text;
        _pageLinks[pageNumber] = links;
      } finally {
        _loadingPageText.remove(pageNumber);
      }
    }
  }

  void _clearPageTextCaches() {
    _pageTexts.clear();
    _pageLinks.clear();
    _loadingPageText.clear();
    _clearSelection();
  }

  // ---- selection model ----

  (_SelPoint, _SelPoint)? get _normalizedSelection {
    final anchor = _selAnchor;
    final focus = _selFocus;
    if (anchor == null || focus == null || anchor == focus) return null;
    return anchor.compareTo(focus) <= 0 ? (anchor, focus) : (focus, anchor);
  }

  bool get _hasSelection => _normalizedSelection != null;

  /// The character range of [pageIndex] covered by a selection spanning
  /// [start] to [end] (inclusive start, exclusive end, per the usual
  /// convention here — see [_SelPoint]), clamped to [length]. Shared by
  /// every place that needs "how much of this page is selected": the
  /// three previously each re-derived it themselves, with a shared bug
  /// (say, an off-by-one at a page boundary) only one edit away from
  /// slipping in between them.
  ({int from, int to}) _selectionRangeForPage(
    int pageIndex,
    _SelPoint start,
    _SelPoint end,
    int length,
  ) {
    final from = pageIndex == start.pageIndex ? start.charIndex : 0;
    final to = pageIndex == end.pageIndex
        ? end.charIndex.clamp(0, length)
        : length;
    return (from: from, to: to);
  }

  TypstTextSelection? get _publicSelection {
    final selection = _normalizedSelection;
    if (selection == null) return null;
    final (start, end) = selection;
    final rects = <TypstTextSelectionRect>[];
    for (
      var pageIndex = start.pageIndex;
      pageIndex <= end.pageIndex;
      pageIndex++
    ) {
      final text = _pageTexts[pageIndex + 1];
      if (text == null) continue;
      final (:from, :to) = _selectionRangeForPage(
        pageIndex,
        start,
        end,
        text.charRects.length,
      );
      for (final rect in text.rectsForRange(from, to)) {
        rects.add(
          TypstTextSelectionRect(
            pageNumber: pageIndex + 1,
            rect: rect.toRect(),
          ),
        );
      }
    }
    return TypstTextSelection(
      start: TypstTextPosition(
        pageNumber: start.pageIndex + 1,
        offset: start.charIndex,
      ),
      end: TypstTextPosition(
        pageNumber: end.pageIndex + 1,
        offset: end.charIndex,
      ),
      text: _selectedText(),
      rects: List.unmodifiable(rects),
    );
  }

  void _clearSelection() {
    if (_selAnchor == null && _selFocus == null) return;
    _selAnchor = null;
    _selFocus = null;
    _toolbarAnchor = null;
    // Normally cleared by the dragged handle's own onPanEnd — but a lost or
    // interrupted gesture (the platform never delivering an up/cancel event
    // for whatever reason) would otherwise leave the magnifier stuck on
    // screen forever, with no handle left to drag and thus no way for the
    // user to ever trigger that onPanEnd. Clearing it here too means at
    // least tapping anywhere to dismiss the selection also recovers from
    // that.
    _draggingHandleIsStart = null;
    _handleDragPoint = null;
    _handleDragFixedEnd = null;
    _handleDragMovingPoint = null;
    _handleDragGrabOffset = null;
    _selectionChanged();
  }

  /// The selected text across pages.
  String _selectedText() {
    final selection = _normalizedSelection;
    if (selection == null) return '';
    final (start, end) = selection;
    final parts = <String>[];
    for (
      var pageIndex = start.pageIndex;
      pageIndex <= end.pageIndex;
      pageIndex++
    ) {
      final text = _pageTexts[pageIndex + 1];
      if (text == null) continue;
      final (:from, :to) = _selectionRangeForPage(
        pageIndex,
        start,
        end,
        text.fullText.length,
      );
      if (from < to) parts.add(text.fullText.substring(from, to));
    }
    return parts.join('\n');
  }

  Future<void> _copySelection() async {
    final text = _selectedText();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _toolbarAnchor = null;
    _repaint();
  }

  /// Selection highlight rects for one page, in document coordinates.
  List<Rect> _selectionRectsForPage(int pageIndex, Rect pageRect) {
    final selection = _normalizedSelection;
    if (selection == null) return const [];
    final (start, end) = selection;
    if (pageIndex < start.pageIndex || pageIndex > end.pageIndex) {
      return const [];
    }
    final text = _pageTexts[pageIndex + 1];
    if (text == null) return const [];
    final (:from, :to) = _selectionRangeForPage(
      pageIndex,
      start,
      end,
      text.charRects.length,
    );
    return [
      for (final rect in text.rectsForRange(from, to))
        rect.toRectInDocument(pageRect),
    ];
  }

  // ---- hit testing (document coordinates) ----

  /// The page under the point, or null.
  int? _pageIndexAt(Offset docPoint) {
    final layout = _layout;
    if (layout == null) return null;
    for (var i = 0; i < layout.pageRects.length; i++) {
      if (layout.pageRects[i].contains(docPoint)) return i;
    }
    return null;
  }

  /// The character under the document point, or null.
  _SelPoint? _charPointAt(Offset docPoint, {double tolerance = 4}) {
    final layout = _layout;
    final pageIndex = _pageIndexAt(docPoint);
    if (layout == null || pageIndex == null) return null;
    final text = _pageTexts[pageIndex + 1];
    if (text == null) return null;
    final pageRect = layout.pageRects[pageIndex];
    final index = text.getCharIndexAt(
      docPoint.dx - pageRect.left,
      docPoint.dy - pageRect.top,
      tolerance: tolerance,
    );
    if (index < 0) return null;
    return _SelPoint(pageIndex, index);
  }

  /// Whether the point is over a character rect (not merely near one).
  bool _isOverText(Offset docPoint) {
    final layout = _layout;
    final pageIndex = _pageIndexAt(docPoint);
    if (layout == null || pageIndex == null) return false;
    final text = _pageTexts[pageIndex + 1];
    if (text == null) return false;
    final pageRect = layout.pageRects[pageIndex];
    final local = docPoint - pageRect.topLeft;
    for (final rect in text.charRects) {
      if (rect.containsPoint(local)) return true;
    }
    return false;
  }

  /// The link under the document point, or null.
  TypstLink? _linkAt(Offset docPoint) {
    final layout = _layout;
    final pageIndex = _pageIndexAt(docPoint);
    if (layout == null || pageIndex == null) return null;
    final links = _pageLinks[pageIndex + 1];
    if (links == null) return null;
    final pageRect = layout.pageRects[pageIndex];
    final local = docPoint - pageRect.topLeft;
    for (final link in links) {
      if (link.rect.containsPoint(local)) return link;
    }
    return null;
  }

  // ---- gestures ----
  //
  // The gesture surface sits above (outside) the zoom Transform, so event
  // positions arrive in view coordinates; every handler converts to document
  // coordinates via [_viewToDoc] before hit-testing pages/text/links.

  void _onTapUp(TapUpDetails details) {
    final link = _linkAt(_viewToDoc(details.localPosition));
    if (link != null) {
      _handleLinkTap(link);
      return;
    }
    _clearSelection();
  }

  void _handleLinkTap(TypstLink link) {
    if (link.dest != null) {
      _goToDest(link.dest!);
    }
    widget.params.onLinkTap?.call(link);
  }

  void _goToDest(TypstDest dest) {
    final layout = _layout;
    if (layout == null || layout.pageRects.isEmpty) return;
    final pageRect = layout
        .pageRects[(dest.pageNumber - 1).clamp(0, layout.pageRects.length - 1)];
    final y = pageRect.top + (dest.y ?? 0);
    _goTo(Offset(_visibleRect.left, y - widget.params.margin));
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (!widget.params.enableTextSelection) return;
    _selectWordAt(_viewToDoc(details.localPosition));
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (!widget.params.enableTextSelection) return;
    _selectWordAt(_viewToDoc(details.localPosition), showToolbar: true);
  }

  void _selectWordAt(Offset docPoint, {bool showToolbar = false}) {
    final point = _charPointAt(docPoint);
    if (point == null) return;
    final text = _pageTexts[point.pageIndex + 1]!;
    final (start, end) = text.wordBoundaryAt(point.charIndex);
    _selAnchor = _SelPoint(point.pageIndex, start);
    _selFocus = _SelPoint(point.pageIndex, end);
    _toolbarAnchor = showToolbar ? docPoint : null;
    _selectionChanged();
  }

  // Mouse drag selection.

  void _onSelectionDragStart(DragStartDetails details) {
    if (!widget.params.enableTextSelection) return;
    _toolbarAnchor = null;
    final point = _charPointAt(_viewToDoc(details.localPosition), tolerance: 2);
    _selAnchor = point;
    _selFocus = point;
    _selectionChanged();
  }

  void _onSelectionDragUpdate(DragUpdateDetails details) {
    if (_selAnchor == null) return;
    final point = _charPointAt(
      _viewToDoc(details.localPosition),
      tolerance: 40,
    );
    if (point != null && point != _selFocus) {
      // Selecting past a character means including it: extend forward by one
      // when the focus is after the anchor.
      _selFocus = _selAnchor!.compareTo(point) <= 0
          ? _SelPoint(point.pageIndex, point.charIndex + 1)
          : point;
      _selectionChanged();
    }
  }

  void _onSelectionDragEnd(DragEndDetails details) {
    if (!_hasSelection) _clearSelection();
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    if (!_hasSelection) return;
    _toolbarAnchor = _viewToDoc(details.localPosition);
    _repaint();
  }

  // ---- hover cursor ----

  void _onHover(PointerHoverEvent event) {
    final point = _viewToDoc(event.localPosition);
    final MouseCursor cursor;
    if (_linkAt(point) != null) {
      cursor = SystemMouseCursors.click;
    } else if (widget.params.enableTextSelection && _isOverText(point)) {
      cursor = SystemMouseCursors.text;
    } else {
      cursor = MouseCursor.defer;
    }
    if (cursor != _hoverCursor) {
      _hoverCursor = cursor;
      _repaint();
    }
  }

  // ---- coordinate conversion ----
  //
  // _txController.value maps document points -> view (screen) coordinates,
  // matching the Transform applied to the painted content.

  Offset _viewToDoc(Offset viewPoint) => MatrixUtils.transformPoint(
    Matrix4.inverted(_txController.value),
    viewPoint,
  );

  Offset _docToView(Offset docPoint) =>
      MatrixUtils.transformPoint(_txController.value, docPoint);

  List<Widget> _buildSelectionOverlay(BuildContext context) {
    final widgets = <Widget>[];
    final selection = _normalizedSelection;
    final layout = _layout;
    if (layout == null) return widgets;

    // Toolbar first, handles last: the start handle's flag (see below) can
    // land close to — or overlapping — a freshly shown copy toolbar for a
    // short selection, and the handle needs to win that overlap to stay
    // draggable. Order in this list is z-order (later = front, and hit-
    // tested first), so the handles loop has to run after this block.
    //
    // Every widget added below carries an explicit Key. Without one, this
    // being a plain unkeyed list means Flutter's Stack reconciles children
    // by *list position*, not identity — and the toolbar (this one) comes
    // and goes independently of the handles (e.g. _onHandleDrag clears
    // _toolbarAnchor mid-drag), which would shift every later widget's
    // list index by one and make Flutter tear down and recreate their
    // Elements, silently losing whichever handle's GestureDetector had an
    // in-flight drag — the pointer's route would be dropped and
    // onPanUpdate would simply stop firing partway through a drag.
    final toolbarAnchor = _toolbarAnchor;
    if (selection != null &&
        toolbarAnchor != null &&
        widget.params.showSelectionToolbar) {
      final view = _docToView(toolbarAnchor);
      // The default `view.dy - 56` placement assumes nothing else occupies
      // that space above the touch point — true for a mouse selection
      // (no handles), but not for a touch one: the start handle's own
      // flag reaches a further _handleSize above the selection's top edge
      // (see the loop below), and a short selection's toolbar can land
      // right on top of it otherwise. Push the toolbar up further still
      // when that handle's box would otherwise reach into it — 48 is a
      // rough estimate of the toolbar's own height, since its real size
      // isn't known until after it's laid out.
      final startRect = _lastInputWasTouch
          ? _charRectInDocument(selection.$1, isStart: true)
          : null;
      final defaultTop = view.dy - 56;
      final top = startRect == null
          ? defaultTop
          : math.min(
              defaultTop,
              _docToView(startRect.topLeft).dy - _handleSize - 48 - 8,
            );
      widgets.add(
        Positioned(
          key: const ValueKey('selection-toolbar'),
          left: math.max(view.dx - 40, 8),
          top: math.max(top, 8),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _copySelection,
                    child: Text(
                      MaterialLocalizations.of(context).copyButtonLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (selection != null && _lastInputWasTouch) {
      for (final (point, isStart) in [
        (selection.$1, true),
        (selection.$2, false),
      ]) {
        final rect = _charRectInDocument(point, isStart: isStart);
        if (rect == null) continue;
        // The start handle's own bottom-right corner (30,30) anchors to the
        // selection's *top*-left text edge, so the whole flag sits above
        // and clear of the selected text (tip touching the top corner,
        // body hanging further up) — the end handle's top-left corner
        // (0,0) anchors to the bottom-right edge, hanging below instead.
        // Same attachment pdfrx uses (its aRight/aBottom vs. bLeft/bTop
        // insets), expressed here as a direct top-left offset since this
        // Positioned's parent Stack fills the viewport.
        final anchor = _docToView(isStart ? rect.topLeft : rect.bottomRight);
        final view = isStart
            ? anchor - const Offset(_handleSize, _handleSize)
            : anchor;
        final isDragging = _handleDragMovingPoint == point;
        widgets.add(
          Positioned(
            key: ValueKey(isStart ? 'start-handle' : 'end-handle'),
            left: view.dx,
            top: view.dy,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                _draggingHandleIsStart = isStart;
                _handleDragFixedEnd = isStart ? selection.$2 : selection.$1;
                _handleDragMovingPoint = point;
                // The row's center, not the box edge `anchor` itself — see
                // the matching comment in _onHandleDrag for why.
                _handleDragPoint = _docToView(rect.center);
                // A human finger rarely lands exactly on the anchor pixel —
                // it lands somewhere on the visible 30x30 flag, which for the
                // start handle hangs up-left of the text edge and for the end
                // handle hangs down-right of it (see the flag placement
                // comment above). Capturing that initial offset and re-adding
                // it every frame (_onHandleDrag) keeps hit-testing pinned to
                // "anchor + how far the finger has moved" instead of
                // "wherever the finger literally is" — without it, the
                // vertical component of that grab offset alone (up to a full
                // flag height) was enough to make the drag pick the wrong
                // character/row.
                _handleDragGrabOffset =
                    anchor - (details.globalPosition - _viewOrigin());
                _repaint();
              },
              onPanUpdate: _onHandleDrag,
              onPanEnd: (_) {
                _draggingHandleIsStart = null;
                _handleDragPoint = null;
                _handleDragFixedEnd = null;
                _handleDragMovingPoint = null;
                _handleDragGrabOffset = null;
                _repaint();
              },
              child: CustomPaint(
                size: const Size(_handleSize, _handleSize),
                painter: _TriangleHandlePainter(
                  path: isStart ? _startHandlePath() : _endHandlePath(),
                  color: widget.params.selectionColor.withAlpha(0xff),
                  state: isDragging
                      ? _HandleState.dragging
                      : _HandleState.normal,
                ),
              ),
            ),
          ),
        );
      }
    }

    if (_draggingHandleIsStart != null && _handleDragPoint != null) {
      widgets.add(_buildMagnifier(_handleDragPoint!));
    }

    return widgets;
  }

  /// A loupe over [focalPoint] (view/screen coordinates) — shown only while
  /// a selection handle is actively being dragged (see
  /// [_draggingHandleIsStart]). Floats above the touch point so the
  /// dragging finger doesn't cover the very text it's positioning over;
  /// [RawMagnifier] sources its magnified image from whatever is already
  /// painted below it in this same overlay (a [BackdropFilter] under the
  /// hood — no separate re-render needed), so it stays in sync with
  /// whatever resolution the page is currently rendered at.
  Widget _buildMagnifier(Offset focalPoint) {
    return Positioned(
      key: const ValueKey('selection-magnifier'),
      left: focalPoint.dx - _magnifierSize.width / 2,
      top:
          focalPoint.dy - _magnifierAboveFocalPoint - _magnifierSize.height / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: _magnifierSize,
          magnificationScale: _magnifierScale,
          // RawMagnifier.focalPointOffset is measured from the magnifier's
          // own *center* (see its doc comment's worked example), not its
          // top edge: content shown at the magnifier's center is sourced
          // from (widget center) + focalPointOffset. The widget's center
          // already sits `_magnifierAboveFocalPoint` above `focalPoint`
          // (see `top` above, which offsets by that plus half the
          // magnifier's own height to place its *top* edge), so this only
          // needs to correct for that same `_magnifierAboveFocalPoint` —
          // adding `_magnifierSize.height / 2` again here (as an earlier
          // version of this code did) double-counts it, shifting the
          // sampled content down by that much and leaving only the bottom
          // half of, e.g., the selection highlight visible.
          focalPointOffset: const Offset(0, _magnifierAboveFocalPoint),
          // Rounded-rect + shadow, matching pdfrx's
          // _buildMagnifierDecoration exactly (BorderRadius.circular(30),
          // Colors.black26 shadow, blur 8 / spread 2) rather than the
          // circular pill this used before.
          decoration: MagnifierDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_magnifierBorderRadius),
            ),
            shadows: const [
              BoxShadow(
                color: Color(0x42000000),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Rect? _charRectInDocument(_SelPoint point, {required bool isStart}) {
    final layout = _layout;
    final text = _pageTexts[point.pageIndex + 1];
    if (layout == null || text == null || text.charRects.isEmpty) return null;
    final index = (isStart ? point.charIndex : point.charIndex - 1).clamp(
      0,
      text.charRects.length - 1,
    );
    return text.charRects[index].toRectInDocument(
      layout.pageRects[point.pageIndex],
    );
  }

  // Keeps the *other* handle's position stable across the whole drag by
  // referencing the value captured once in onPanStart (_handleDragFixedEnd)
  // rather than re-deriving "the other endpoint" from _normalizedSelection
  // each frame. That re-derivation was an earlier bug: _normalizedSelection
  // swaps its two points as soon as the dragged one crosses the other, so
  // whichever of _selAnchor/_selFocus this function treated as "the fixed
  // side" would suddenly become last frame's *moving* value instead of the
  // true fixed one — collapsing the selection to a near-zero span one frame
  // after crossing, instead of properly flipping which handle is which.
  void _onHandleDrag(DragUpdateDetails details) {
    final fixed = _handleDragFixedEnd;
    if (fixed == null) return;
    // The handle lives in view coordinates; convert to document space. The
    // grab offset captured in onPanStart is re-added here so the pinned
    // point tracks "anchor + finger delta since the drag started" rather
    // than the raw finger position — see that handler's comment.
    final rawViewPoint = details.globalPosition - _viewOrigin();
    final viewPoint = rawViewPoint + (_handleDragGrabOffset ?? Offset.zero);
    _handleDragPoint =
        viewPoint; // fallback while nothing's hit yet; refined below once a char is
    final docPoint = MatrixUtils.transformPoint(
      Matrix4.inverted(_txController.value),
      viewPoint,
    );
    final char = _charPointAt(docPoint, tolerance: 40);
    if (char == null) {
      _repaint(); // still need to redraw the magnifier at its new position
      return;
    }
    // The magnifier's *vertical* focus locks onto the hit character's own
    // row center rather than following the (grab-offset-compensated)
    // finger's literal y — pdfrx's own magnified content rect is likewise
    // centered on the character's height with only slight (~0.2x) vertical
    // jitter, never tied straight to the touch point. Without this, the
    // compensated y can coincide with a character rect's *edge* (its full
    // line-height box, not just its visible ink) rather than its center —
    // reachable in particular by holding the finger steady vertically
    // while sliding it horizontally — leaving the magnifier sampling
    // mostly blank leading space instead of the selected text. Horizontal
    // still follows the finger directly: pdfrx's own rect is far more
    // permissive there (±2x the char height) since precisely which column
    // the finger is over matters less once the row itself is locked in.
    final charRect = _charRectInDocument(char, isStart: true);
    if (charRect != null) {
      _handleDragPoint = Offset(viewPoint.dx, _docToView(charRect.center).dy);
    }
    // Which side of the selection `char` becomes is decided by its
    // relationship to `fixed`, never by which literal handle (start or
    // end) is under the finger — that used to be a fixed per-drag
    // "isStart ? char : char+1" rule, and it could put `moving` exactly on
    // top of `fixed` (e.g. dragging the end handle left until it lands on
    // the untouched start boundary: char+1 == fixed) collapsing the
    // selection to empty, tearing down the very handles mid-drag that were
    // supposed to keep receiving this gesture. Comparing to `fixed` here
    // instead guarantees `moving` always lands strictly on one side of it:
    // >= fixed becomes the exclusive end (char+1, so it's strictly greater,
    // never equal), < fixed stays the inclusive start (char, already
    // strictly less) — self-consistent with how _normalizedSelection sorts
    // and renders start/end either way, so which handle is physically
    // being dragged no longer needs to be threaded through this function.
    final moving = char.compareTo(fixed) >= 0
        ? _SelPoint(char.pageIndex, char.charIndex + 1)
        : char;
    // Matches selection.$1/$2's own convention (the render loop's `point`,
    // used for the isDragging comparison there) rather than the raw
    // hit-tested character — those two can differ by the +1 above.
    _handleDragMovingPoint = moving;
    final previousAnchor = _selAnchor;
    final previousFocus = _selFocus;
    if (moving.compareTo(fixed) <= 0) {
      _selAnchor = moving;
      _selFocus = fixed;
    } else {
      _selAnchor = fixed;
      _selFocus = moving;
    }
    _toolbarAnchor = null;
    // Sub-character finger jitter frequently re-hits the same character as
    // last frame — _onSelectionDragUpdate above already only notifies on an
    // actual change; this matches that, rather than reallocating the public
    // selection and firing the host callback/controller listeners on every
    // pan-update tick regardless. The magnifier still needs to move though
    // (see _handleDragPoint above), so a plain repaint replaces it when
    // nothing about the selection itself changed.
    if (_selAnchor != previousAnchor || _selFocus != previousFocus) {
      _selectionChanged();
    } else {
      _repaint();
    }
  }

  Offset _viewOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    return box?.localToGlobal(Offset.zero) ?? Offset.zero;
  }
}
