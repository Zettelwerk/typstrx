part of 'typst_viewer.dart';

/// Programmatic control over a [TypstViewer].
///
/// Listens like a `ValueListenable<Matrix4>`: notifications fire whenever the
/// view transform (scroll position or zoom) changes.
class TypstViewerController extends ChangeNotifier
    implements ValueListenable<Matrix4> {
  _TypstViewerState? _state;

  bool get isReady => _state != null && _state!._layout != null;

  /// The current view matrix (document points -> view coordinates).
  @override
  Matrix4 get value =>
      _state?._txController.value ?? Matrix4.identity();

  /// The current zoom (1.0 = one point per logical pixel).
  double get currentZoom => _state?._currentZoom ?? 1.0;

  /// The part of the document (in points) currently visible.
  Rect get visibleRect => _state?._visibleRect ?? Rect.zero;

  /// The page number whose area dominates the viewport (1-based; 0 when no
  /// document is loaded).
  int get currentPageNumber => _state?._currentPageNumber ?? 0;

  /// The rasterization scale (in pixels per point; 1pt = 1/72in, so
  /// `scale * 72` is the effective DPI — see [currentRasterDpi]) of the
  /// sharpest image currently painted for [currentPageNumber].
  ///
  /// This is the *actual* resolution on screen right now, which lags the
  /// target resolution implied by [currentZoom] while a (re)render is in
  /// flight — e.g. right after zooming in, before the sharper tile has
  /// finished rendering. Changes are included in this controller's
  /// notifications, so listen to it to keep a readout in sync.
  double get currentRasterScale => _state?._currentRasterScale ?? 1.0;

  /// [currentRasterScale] expressed in DPI (dots/pixels per inch) —
  /// `currentRasterScale * 72`, matching the units of
  /// [TypstViewerParams.maxRenderDpi]/[TypstViewerParams.previewDpi].
  double get currentRasterDpi => currentRasterScale * _pointsPerInch;

  /// Metrics for the most recently completed page render (preview or hi-res
  /// tile), across all pages — pixel size, scale, and wall-clock render
  /// time. Null until the first render completes. Useful for tuning
  /// [TypstViewerParams.maxRenderDpi]/[TypstViewerParams.previewDpi] against
  /// real render costs.
  RasterizationMetrics? get lastRender => _state?._cache.lastRender;

  /// Total bytes currently held by the page image cache, across both tiers.
  int get cacheBytes => _state?._cache.totalBytes ?? 0;

  /// Number of page images (previews + tiles) currently cached.
  int get cachedImageCount => _state?._cache.cachedImageCount ?? 0;

  /// Scrolls so that the top of [pageNumber] is visible, keeping the zoom.
  void goToPage(int pageNumber) {
    final state = _state;
    final layout = state?._layout;
    if (state == null || layout == null) return;
    final rect = layout.pageRects[
        (pageNumber - 1).clamp(0, layout.pageRects.length - 1)];
    state._goTo(Offset(state._visibleRect.left, rect.top - 8));
  }

  /// Sets the zoom, keeping [focalPoint] (in view coordinates, defaults to
  /// the view center) fixed on screen.
  void setZoom(double zoom, {Offset? focalPoint}) {
    _state?._setZoom(zoom, focalPoint: focalPoint);
  }

  /// Scrolls to an internal link destination.
  void goToDest(TypstDest dest) => _state?._goToDest(dest);

  /// The currently selected text (empty when nothing is selected).
  String get selectedText => _state?._selectedText() ?? '';

  /// The current rendered-text selection, including page-local geometry.
  TypstTextSelection? get selection => _state?._publicSelection;

  /// Clears the text selection.
  void clearSelection() => _state?._clearSelection();

  void _notifySelectionChanged() => notifyListeners();

  void _attach(_TypstViewerState state) {
    _state = state;
    state._txController.addListener(notifyListeners);
    // Also notify when cached images change — e.g. currentRasterScale
    // updates when a sharper tile finishes rendering, not just on pan/zoom.
    state._cache.addListener(notifyListeners);
  }

  void _detach() {
    _state?._txController.removeListener(notifyListeners);
    _state?._cache.removeListener(notifyListeners);
    _state = null;
  }
}
