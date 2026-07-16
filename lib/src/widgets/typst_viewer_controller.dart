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

  void _attach(_TypstViewerState state) {
    _state = state;
    state._txController.addListener(notifyListeners);
  }

  void _detach() {
    _state?._txController.removeListener(notifyListeners);
    _state = null;
  }
}
