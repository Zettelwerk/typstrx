import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../document/typst_document.dart';
import '../document/typst_page.dart';
import '../document/typst_session.dart';
import 'typst_page_image_cache.dart';
import 'typst_viewer_params.dart';

part 'typst_viewer_controller.dart';

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

  // ---- wheel handling (registered on the resolver so it wins against
  // InteractiveViewer's own scroll-to-pan) ----

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scrollEvent = event as PointerScrollEvent;
      if (HardwareKeyboard.instance.isControlPressed) {
        final delta =
            -(scrollEvent.scrollDelta.dx + scrollEvent.scrollDelta.dy) / 120.0;
        final newZoom = _currentZoom * math.pow(1.2, delta);
        final box = context.findRenderObject() as RenderBox?;
        final local = box?.globalToLocal(scrollEvent.position);
        _setZoom(newZoom.toDouble(), focalPoint: local);
      } else {
        final matrix = _txController.value.clone()
          ..translateByDouble(
            -scrollEvent.scrollDelta.dx / _currentZoom,
            -scrollEvent.scrollDelta.dy / _currentZoom,
            0,
            1,
          );
        _txController.value = _clampMatrix(matrix);
      }
    });
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
        return ColoredBox(
          color: widget.params.backgroundColor,
          child: InteractiveViewer(
            transformationController: _txController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: widget.params.minScale,
            maxScale: widget.params.maxScale,
            onInteractionEnd: (_) {
              _txController.value = _clampMatrix(_txController.value);
            },
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: CustomPaint(
                size: layout.documentSize,
                painter: _TypstDocumentPainter(this),
              ),
            ),
          ),
        );
      },
    );
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
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TypstDocumentPainter oldDelegate) => true;
}
