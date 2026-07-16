part of 'typst_viewer.dart';

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

  void _clearSelection() {
    if (_selAnchor == null && _selFocus == null) return;
    _selAnchor = null;
    _selFocus = null;
    _toolbarAnchor = null;
    _repaint();
  }

  /// The selected text across pages.
  String _selectedText() {
    final selection = _normalizedSelection;
    if (selection == null) return '';
    final (start, end) = selection;
    final parts = <String>[];
    for (var pageIndex = start.pageIndex;
        pageIndex <= end.pageIndex;
        pageIndex++) {
      final text = _pageTexts[pageIndex + 1];
      if (text == null) continue;
      final from = pageIndex == start.pageIndex ? start.charIndex : 0;
      final to = pageIndex == end.pageIndex
          ? end.charIndex.clamp(0, text.fullText.length)
          : text.fullText.length;
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
    final from = pageIndex == start.pageIndex ? start.charIndex : 0;
    final to = pageIndex == end.pageIndex
        ? end.charIndex.clamp(0, text.charRects.length)
        : text.charRects.length;
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

  // ---- gestures (positions are document coordinates: the gesture surface
  // lives inside the InteractiveViewer's transformed subtree) ----

  void _onTapUp(TapUpDetails details) {
    final link = _linkAt(details.localPosition);
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
    final pageRect = layout.pageRects[
        (dest.pageNumber - 1).clamp(0, layout.pageRects.length - 1)];
    final y = pageRect.top + (dest.y ?? 0);
    _goTo(Offset(_visibleRect.left, y - widget.params.margin));
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (!widget.params.enableTextSelection) return;
    _selectWordAt(details.localPosition);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (!widget.params.enableTextSelection) return;
    _selectWordAt(details.localPosition, showToolbar: true);
  }

  void _selectWordAt(Offset docPoint, {bool showToolbar = false}) {
    final point = _charPointAt(docPoint);
    if (point == null) return;
    final text = _pageTexts[point.pageIndex + 1]!;
    final (start, end) = text.wordBoundaryAt(point.charIndex);
    _selAnchor = _SelPoint(point.pageIndex, start);
    _selFocus = _SelPoint(point.pageIndex, end);
    _toolbarAnchor = showToolbar ? docPoint : null;
    _repaint();
  }

  // Mouse drag selection.

  void _onSelectionDragStart(DragStartDetails details) {
    if (!widget.params.enableTextSelection) return;
    _toolbarAnchor = null;
    final point = _charPointAt(details.localPosition, tolerance: 2);
    _selAnchor = point;
    _selFocus = point;
    _repaint();
  }

  void _onSelectionDragUpdate(DragUpdateDetails details) {
    if (_selAnchor == null) return;
    final point = _charPointAt(details.localPosition, tolerance: 40);
    if (point != null && point != _selFocus) {
      // Selecting past a character means including it: extend forward by one
      // when the focus is after the anchor.
      _selFocus = _selAnchor!.compareTo(point) <= 0
          ? _SelPoint(point.pageIndex, point.charIndex + 1)
          : point;
      _repaint();
    }
  }

  void _onSelectionDragEnd(DragEndDetails details) {
    if (!_hasSelection) _clearSelection();
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    if (!_hasSelection) return;
    _toolbarAnchor = details.localPosition;
    _repaint();
  }

  // ---- hover cursor ----

  void _onHover(PointerHoverEvent event) {
    final point = event.localPosition;
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

  // ---- toolbar & handles (view coordinates, above the InteractiveViewer) ----

  Offset _docToView(Offset docPoint) =>
      MatrixUtils.transformPoint(_txController.value, docPoint);

  List<Widget> _buildSelectionOverlay(BuildContext context) {
    final widgets = <Widget>[];
    final selection = _normalizedSelection;
    final layout = _layout;
    if (layout == null) return widgets;

    if (selection != null && _lastInputWasTouch) {
      for (final (point, isStart) in [
        (selection.$1, true),
        (selection.$2, false),
      ]) {
        final rect = _charRectInDocument(point, isStart: isStart);
        if (rect == null) continue;
        final view = _docToView(
          isStart ? rect.bottomLeft : rect.bottomRight,
        );
        widgets.add(Positioned(
          left: view.dx - 12,
          top: view.dy - 4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => _onHandleDrag(details, isStart),
            onPanEnd: (_) => _repaint(),
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.topCenter,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: widget.params.selectionColor.withAlpha(0xff),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ));
      }
    }

    final toolbarAnchor = _toolbarAnchor;
    if (selection != null && toolbarAnchor != null) {
      final view = _docToView(toolbarAnchor);
      widgets.add(Positioned(
        left: math.max(view.dx - 40, 8),
        top: math.max(view.dy - 56, 8),
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
      ));
    }
    return widgets;
  }

  Rect? _charRectInDocument(_SelPoint point, {required bool isStart}) {
    final layout = _layout;
    final text = _pageTexts[point.pageIndex + 1];
    if (layout == null || text == null || text.charRects.isEmpty) return null;
    final index =
        (isStart ? point.charIndex : point.charIndex - 1)
            .clamp(0, text.charRects.length - 1);
    return text.charRects[index]
        .toRectInDocument(layout.pageRects[point.pageIndex]);
  }

  void _onHandleDrag(DragUpdateDetails details, bool isStart) {
    final selection = _normalizedSelection;
    if (selection == null) return;
    // The handle lives in view coordinates; convert to document space.
    final docPoint = MatrixUtils.transformPoint(
      Matrix4.inverted(_txController.value),
      details.globalPosition - _viewOrigin(),
    );
    final point = _charPointAt(docPoint, tolerance: 40);
    if (point == null) return;
    if (isStart) {
      _selAnchor = point;
      _selFocus = selection.$2;
    } else {
      _selAnchor = selection.$1;
      _selFocus = _SelPoint(point.pageIndex, point.charIndex + 1);
    }
    _toolbarAnchor = null;
    _repaint();
  }

  Offset _viewOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    return box?.localToGlobal(Offset.zero) ?? Offset.zero;
  }
}
