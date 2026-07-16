import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show Material, MaterialLocalizations, TextButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../document/typst_document.dart';
import '../document/typst_link.dart';
import '../document/typst_page.dart';
import '../document/typst_session.dart';
import '../document/typst_text.dart';
import 'typst_page_image_cache.dart';
import 'typst_viewer_params.dart';

part 'typst_viewer_controller.dart';
part 'typst_viewer_selection.dart';

/// Positions of all pages in document coordinates (points).
class TypstPageLayout {
  const TypstPageLayout({required this.pageRects, required this.documentSize});

  /// One rect per page, in document points.
  final List<Rect> pageRects;

  /// Total size of the virtual document canvas, in points.
  final Size documentSize;
}

/// Displays the pages of a [TypstSession]'s compiled document with pan/zoom
/// and lazily rendered page images.
///
/// The viewer follows the session: every successful recompilation updates the
/// shown document in place, keeping the previous images visible until the
/// replacements are rendered.
class TypstViewer extends StatefulWidget {
  const TypstViewer({
    super.key,
    required this.session,
    this.controller,
    this.params = const TypstViewerParams(),
  });

  /// The session whose latest document is displayed.
  final TypstSession session;

  /// Optional controller for programmatic scrolling/zooming.
  final TypstViewerController? controller;

  /// Visual and behavioral configuration.
  final TypstViewerParams params;

  @override
  State<TypstViewer> createState() => _TypstViewerState();
}

class _TypstViewerState extends State<TypstViewer> {
  final _txController = TransformationController();
  late TypstPageImageCache _cache;
  StreamSubscription<TypstDocument>? _subscription;

  TypstDocument? _document;
  TypstPageLayout? _layout;
  Size? _viewSize;
  double _devicePixelRatio = 1.0;
  bool _fitDone = false;
  Timer? _renderTimer;

  // Text selection & links (see typst_viewer_selection.dart).
  final _pageTexts = <int, TypstPageText>{};
  final _pageLinks = <int, List<TypstLink>>{};
  final _loadingPageText = <int>{};
  _SelPoint? _selAnchor;
  _SelPoint? _selFocus;
  Offset? _toolbarAnchor;
  MouseCursor _hoverCursor = MouseCursor.defer;
  bool _lastInputWasTouch = false;

  // Touch pan/pinch-zoom gesture state (see _onGestureScale*).
  double? _gestureStartZoom;
  Offset? _gestureReferenceFocalPoint;

  @override
  void initState() {
    super.initState();
    _cache = TypstPageImageCache(maxBytes: widget.params.maxImageCacheBytes);
    widget.controller?._attach(this);
    _txController.addListener(_onMatrixChanged);
    _subscription = widget.session.documents.listen(_onDocument);
    final initial = widget.session.document;
    if (initial != null) _onDocument(initial);
  }

  @override
  void didUpdateWidget(TypstViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
    if (oldWidget.session != widget.session) {
      _subscription?.cancel();
      _subscription = widget.session.documents.listen(_onDocument);
      _document = null;
      _layout = null;
      _fitDone = false;
      final initial = widget.session.document;
      if (initial != null) _onDocument(initial);
    }
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    _subscription?.cancel();
    widget.controller?._detach();
    _txController.removeListener(_onMatrixChanged);
    _txController.dispose();
    _cache.dispose();
    super.dispose();
  }

  void _onDocument(TypstDocument document) {
    if (!mounted) return;
    setState(() {
      _document = document;
      _layout = _layoutPages(document);
      _cache.removePagesAbove(document.pages.length);
      _clearPageTextCaches();
    });
    _scheduleRender();
  }

  TypstPageLayout _layoutPages(TypstDocument document) {
    final margin = widget.params.margin;
    var maxWidth = 0.0;
    for (final page in document.pages) {
      maxWidth = math.max(maxWidth, page.width);
    }
    final docWidth = maxWidth + margin * 2;
    final rects = <Rect>[];
    var top = margin;
    for (final page in document.pages) {
      rects.add(Rect.fromLTWH(
        (docWidth - page.width) / 2,
        top,
        page.width,
        page.height,
      ));
      top += page.height + margin;
    }
    return TypstPageLayout(
      pageRects: rects,
      documentSize: Size(docWidth, top),
    );
  }

  // ---- view transform ----

  double get _currentZoom => _txController.value.getMaxScaleOnAxis();

  Rect get _visibleRect {
    final viewSize = _viewSize;
    if (viewSize == null) return Rect.zero;
    final inverse = Matrix4.inverted(_txController.value);
    final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(viewSize.width, viewSize.height),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  int get _currentPageNumber {
    final layout = _layout;
    if (layout == null || layout.pageRects.isEmpty) return 0;
    final visible = _visibleRect;
    var best = 1;
    var bestArea = -1.0;
    for (var i = 0; i < layout.pageRects.length; i++) {
      final intersection = layout.pageRects[i].intersect(visible);
      final area = intersection.isEmpty
          ? -_distance(layout.pageRects[i], visible)
          : intersection.width * intersection.height;
      if (area > bestArea) {
        bestArea = area;
        best = i + 1;
      }
    }
    return best;
  }

  static double _distance(Rect a, Rect b) {
    final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right));
    final dy = math.max(0.0, math.max(a.top - b.bottom, b.top - a.bottom));
    return math.sqrt(dx * dx + dy * dy);
  }

  void _onMatrixChanged() {
    _scheduleRender();
  }

  /// Repaint request from the selection/link layer.
  void _repaint() {
    if (mounted) setState(() {});
  }

  /// Scrolls the view so that the given document offset lands at the top-left
  /// (clamped to the document bounds).
  void _goTo(Offset documentOffset) {
    final zoom = _currentZoom;
    final matrix = Matrix4.identity()
      // z is scaled too so getMaxScaleOnAxis stays correct for zoom < 1.
      ..scaleByDouble(zoom, zoom, zoom, 1)
      ..translateByDouble(-documentOffset.dx, -documentOffset.dy, 0, 1);
    _txController.value = _clampMatrix(matrix);
  }

  void _setZoom(double zoom, {Offset? focalPoint}) {
    final viewSize = _viewSize;
    if (viewSize == null) return;
    final clamped = clampDouble(
      zoom,
      widget.params.minScale,
      widget.params.maxScale,
    );
    final focal = focalPoint ??
        Offset(viewSize.width / 2, viewSize.height / 2);
    final docPoint = MatrixUtils.transformPoint(
      Matrix4.inverted(_txController.value),
      focal,
    );
    final matrix = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(clamped, clamped, clamped, 1)
      ..translateByDouble(-docPoint.dx, -docPoint.dy, 0, 1);
    _txController.value = _clampMatrix(matrix);
  }

  /// Keeps the document inside the view: when the scaled document is larger
  /// than the view it may not be panned off-screen; when it is smaller it is
  /// centered on that axis.
  Matrix4 _clampMatrix(Matrix4 matrix) {
    final layout = _layout;
    final viewSize = _viewSize;
    if (layout == null || viewSize == null) return matrix;
    final zoom = matrix.getMaxScaleOnAxis();
    final docWidth = layout.documentSize.width * zoom;
    final docHeight = layout.documentSize.height * zoom;
    var tx = matrix.storage[12];
    var ty = matrix.storage[13];
    if (docWidth <= viewSize.width) {
      tx = (viewSize.width - docWidth) / 2;
    } else {
      tx = clampDouble(tx, viewSize.width - docWidth, 0);
    }
    if (docHeight <= viewSize.height) {
      ty = (viewSize.height - docHeight) / 2;
    } else {
      ty = clampDouble(ty, viewSize.height - docHeight, 0);
    }
    final result = matrix.clone();
    result.storage[12] = tx;
    result.storage[13] = ty;
    return result;
  }

  /// Initial fit: page width fills the view (capped by maxScale).
  void _fitInitialView() {
    final layout = _layout;
    final viewSize = _viewSize;
    if (layout == null || viewSize == null || _fitDone) return;
    _fitDone = true;
    final zoom = clampDouble(
      viewSize.width / layout.documentSize.width,
      widget.params.minScale,
      widget.params.maxScale,
    );
    _txController.value = _clampMatrix(
      Matrix4.identity()..scaleByDouble(zoom, zoom, zoom, 1),
    );
  }

  // ---- wheel handling ----
  //
  // We don't use the stock InteractiveViewer for gestures (see
  // _documentGestures/_onGestureScale* below), so this is the only mouse
  // wheel handler in the tree — no pointerSignalResolver coordination needed.

  bool _shouldZoomOnWheel(PointerScrollEvent event) {
    final custom = widget.params.shouldZoomOnWheelScroll;
    if (custom != null) return custom(event);
    final keys = HardwareKeyboard.instance;
    return switch (widget.params.wheelZoomTrigger) {
      WheelZoomTrigger.control => keys.isControlPressed,
      WheelZoomTrigger.shift => keys.isShiftPressed,
      WheelZoomTrigger.alt => keys.isAltPressed,
      WheelZoomTrigger.always => true,
      WheelZoomTrigger.never => false,
    };
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_shouldZoomOnWheel(event)) {
      final delta = -(event.scrollDelta.dx + event.scrollDelta.dy) / 120.0;
      final newZoom = _currentZoom * math.pow(1.2, delta);
      final box = context.findRenderObject() as RenderBox?;
      final local = box?.globalToLocal(event.position);
      _setZoom(newZoom.toDouble(), focalPoint: local);
    } else {
      final matrix = _txController.value.clone()
        ..translateByDouble(
          -event.scrollDelta.dx / _currentZoom,
          -event.scrollDelta.dy / _currentZoom,
          0,
          1,
        );
      _txController.value = _clampMatrix(matrix);
    }
  }

  // ---- touch pan & pinch-zoom ----
  //
  // Mouse is deliberately excluded (see _documentGestures): on desktop,
  // panning is wheel-driven and mouse-drag is reserved for text selection.
  // The math mirrors Flutter's own InteractiveViewer scale handling, minus
  // boundary/rotation handling we don't need (we clamp ourselves).

  void _onGestureScaleStart(ScaleStartDetails details) {
    _gestureStartZoom = _currentZoom;
    _gestureReferenceFocalPoint = MatrixUtils.transformPoint(
      Matrix4.inverted(_txController.value),
      details.localFocalPoint,
    );
  }

  void _onGestureScaleUpdate(ScaleUpdateDetails details) {
    final startZoom = _gestureStartZoom;
    final referenceFocalPoint = _gestureReferenceFocalPoint;
    if (startZoom == null || referenceFocalPoint == null) return;

    final desiredZoom = clampDouble(
      startZoom * details.scale,
      widget.params.minScale,
      widget.params.maxScale,
    );
    final scaleChange =
        _currentZoom == 0 ? 1.0 : desiredZoom / _currentZoom;

    final matrix = _txController.value.clone();
    if (scaleChange != 1.0) {
      matrix.scaleByDouble(scaleChange, scaleChange, scaleChange, 1);
    }

    // Keep the reference document point pinned under the current focal
    // point — this also carries the pan component of the gesture (which is
    // just a scale-1.0 "pin" of a moving focal point).
    final focalPointScene = MatrixUtils.transformPoint(
      Matrix4.inverted(matrix),
      details.localFocalPoint,
    );
    final translation = focalPointScene - referenceFocalPoint;
    matrix.translateByDouble(translation.dx, translation.dy, 0, 1);

    _txController.value = _clampMatrix(matrix);
  }

  void _onGestureScaleEnd(ScaleEndDetails details) {
    _gestureStartZoom = null;
    _gestureReferenceFocalPoint = null;
    _txController.value = _clampMatrix(_txController.value);
  }

  // ---- rendering pipeline ----

  void _scheduleRender() {
    _renderTimer?.cancel();
    _renderTimer = Timer(widget.params.renderDelay, _updateCachedImages);
  }

  Future<void> _updateCachedImages() async {
    final document = _document;
    final layout = _layout;
    if (document == null || layout == null || !mounted) return;

    final visible = _visibleRect;
    final cacheRect = visible.inflate(visible.height / 2);
    final previewScale = clampDouble(
      _currentZoom * _devicePixelRatio,
      0.5,
      widget.params.previewScaleCap,
    );

    final visiblePages = <int>{};
    final toRender = <TypstPage>[];
    for (var i = 0; i < layout.pageRects.length; i++) {
      if (!layout.pageRects[i].overlaps(cacheRect)) continue;
      final pageNumber = i + 1;
      visiblePages.add(pageNumber);
      if (!_cache.hasFreshPreview(
          pageNumber, previewScale, document.generation)) {
        toRender.add(document.pages[i]);
      }
    }

    _cache.evictIfNeeded(visiblePages, _currentPageNumber);

    for (final page in toRender) {
      if (!mounted || _document != document) return;
      await _cache.renderPreview(page, previewScale);
    }

    await _updateTiles(document, layout, visible, previewScale);
    await _preloadPageText(document, visiblePages);
  }

  /// Renders one high-resolution tile per visible page — the visible window
  /// of the page at the device's true scale — whenever the preview tier's
  /// capped scale is not sharp enough.
  Future<void> _updateTiles(
    TypstDocument document,
    TypstPageLayout layout,
    Rect visible,
    double previewScale,
  ) async {
    final tileScale = clampDouble(
      _currentZoom * _devicePixelRatio,
      0.5,
      widget.params.maxRenderScale,
    );
    if (tileScale <= previewScale * 1.05) {
      _cache.pruneTiles(keep: const {});
      return;
    }

    // A modest margin around the viewport so small pans stay sharp without
    // re-rendering.
    final tileWindow = visible.inflate(visible.shortestSide * 0.15);
    final keep = <int>{};
    final requests = <(TypstPage, Rect, Rect)>[];
    for (var i = 0; i < layout.pageRects.length; i++) {
      final pageRect = layout.pageRects[i];
      final tileRect = pageRect.intersect(tileWindow);
      if (tileRect.isEmpty) continue;
      final pageNumber = i + 1;
      keep.add(pageNumber);
      if (!_cache.hasFreshTile(
          pageNumber, tileRect, tileScale, document.generation)) {
        requests.add((document.pages[i], pageRect, tileRect));
      }
    }
    _cache.pruneTiles(keep: keep);

    for (final (page, pageRect, tileRect) in requests) {
      if (!mounted || _document != document) return;
      await _cache.renderTile(page, pageRect, tileRect, tileScale);
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final layout = _layout;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (_viewSize != viewSize) {
          _viewSize = viewSize;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _fitInitialView();
            _txController.value = _clampMatrix(_txController.value);
            _scheduleRender();
          });
        }
        if (layout == null) {
          return ColoredBox(color: widget.params.backgroundColor);
        }
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                _copySelection,
            const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                _copySelection,
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: widget.params.backgroundColor,
                    // Sized explicitly to the viewport (rather than letting
                    // it size to the transformed content) so gestures — most
                    // importantly wheel scroll — are captured everywhere in
                    // the view, not just where a page happens to be painted.
                    child: SizedBox(
                      width: viewSize.width,
                      height: viewSize.height,
                      child: Listener(
                        onPointerSignal: _onPointerSignal,
                        onPointerDown: (event) => _lastInputWasTouch =
                            event.kind == PointerDeviceKind.touch,
                        child: MouseRegion(
                          cursor: _hoverCursor,
                          onHover: _onHover,
                          child: RawGestureDetector(
                            behavior: HitTestBehavior.opaque,
                            gestures: _documentGestures(),
                            child: ClipRect(
                              child: AnimatedBuilder(
                                animation: _txController,
                                builder: (context, child) => Transform(
                                  transform: _txController.value,
                                  child: child,
                                ),
                                child: CustomPaint(
                                  size: layout.documentSize,
                                  painter: _TypstDocumentPainter(this),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ..._buildSelectionOverlay(context),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Gestures on the document surface.
  ///
  /// - Mouse: no pan/pinch recognizer here at all — desktop panning is
  ///   wheel-driven (see [_onPointerSignal]) and mouse-drag is reserved for
  ///   text selection ([_onSelectionDragStart] et al., mouse-only below).
  /// - Touch/stylus: a scale recognizer provides both one-finger drag-pan and
  ///   two-finger pinch-zoom ([_onGestureScaleStart] et al.); text selection
  ///   on touch starts via long-press instead of drag, so there's no
  ///   conflict with panning.
  Map<Type, GestureRecognizerFactory> _documentGestures() {
    return {
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        TapGestureRecognizer.new,
        (recognizer) => recognizer
          ..onTapUp = _onTapUp
          ..onSecondaryTapUp = _onSecondaryTapUp,
      ),
      DoubleTapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
        DoubleTapGestureRecognizer.new,
        (recognizer) => recognizer.onDoubleTapDown = _onDoubleTapDown,
      ),
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        LongPressGestureRecognizer.new,
        (recognizer) => recognizer.onLongPressStart = _onLongPressStart,
      ),
      ScaleGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
        () => ScaleGestureRecognizer(
          supportedDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
          },
        ),
        (recognizer) => recognizer
          ..onStart = _onGestureScaleStart
          ..onUpdate = _onGestureScaleUpdate
          ..onEnd = _onGestureScaleEnd,
      ),
      if (widget.params.enableTextSelection)
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
          () => PanGestureRecognizer(
            supportedDevices: {PointerDeviceKind.mouse},
          ),
          (recognizer) => recognizer
            // Anchor the selection at the press position, not where the
            // recognizer won the gesture arena.
            ..dragStartBehavior = DragStartBehavior.down
            ..onStart = _onSelectionDragStart
            ..onUpdate = _onSelectionDragUpdate
            ..onEnd = _onSelectionDragEnd,
        ),
    };
  }
}

class _TypstDocumentPainter extends CustomPainter {
  _TypstDocumentPainter(this.state)
      : super(
          repaint: Listenable.merge([state._cache, state._txController]),
        );

  final _TypstViewerState state;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = state._layout;
    final document = state._document;
    if (layout == null || document == null) return;

    final visible = state._visibleRect.inflate(state._visibleRect.height / 2);
    final shadow = state.widget.params.pageDropShadow;
    final pagePaint = Paint()..color = const Color(0xffffffff);

    for (var i = 0; i < layout.pageRects.length; i++) {
      final rect = layout.pageRects[i];
      if (!rect.overlaps(visible)) continue;

      if (shadow != null) {
        canvas.drawRect(
          rect.shift(shadow.offset),
          Paint()
            ..color = shadow.color
            ..maskFilter =
                MaskFilter.blur(BlurStyle.normal, shadow.blurRadius / 2),
        );
      }
      canvas.drawRect(rect, pagePaint);

      final imagePaint = Paint()..filterQuality = FilterQuality.medium;
      final cached = state._cache.previewOf(i + 1);
      if (cached != null) {
        canvas.drawImageRect(
          cached.image,
          Rect.fromLTWH(
            0,
            0,
            cached.image.width.toDouble(),
            cached.image.height.toDouble(),
          ),
          rect,
          imagePaint,
        );
      }

      // Sharp visible-window tile on top of the stretched preview.
      final tile = state._cache.tileOf(i + 1, document.generation);
      if (tile != null) {
        canvas.drawImageRect(
          tile.image,
          Rect.fromLTWH(
            0,
            0,
            tile.image.width.toDouble(),
            tile.image.height.toDouble(),
          ),
          tile.rect,
          imagePaint,
        );
      }

      // Selection highlight.
      final selectionRects = state._selectionRectsForPage(i, rect);
      if (selectionRects.isNotEmpty) {
        final selectionPaint = Paint()
          ..color = state.widget.params.selectionColor;
        for (final selectionRect in selectionRects) {
          canvas.drawRect(selectionRect, selectionPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TypstDocumentPainter oldDelegate) => true;
}
