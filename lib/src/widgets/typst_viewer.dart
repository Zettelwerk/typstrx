import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show Colors, Material, MaterialLocalizations, TextButton;
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../document/typst_document.dart';
import '../document/typst_link.dart';
import '../document/typst_page.dart';
import '../document/typst_session.dart';
import '../document/typst_text.dart';
import '../document/typst_text_selection.dart';
import 'typst_page_image_cache.dart';
import 'typst_viewer_params.dart';

part 'typst_viewer_controller.dart';
part 'typst_viewer_selection.dart';

/// 1 Typst point = 1/72 inch — the DPI <-> pixels-per-point conversion
/// factor used throughout rasterization.
const _pointsPerInch = 72.0;

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
    this.document,
    this.initialPreviewImage,
    this.initialPreviewScale,
    this.initialPreviewRenderTime = Duration.zero,
    this.controller,
    this.pageMargin,
    this.params = const TypstViewerParams(),
  }) : assert(pageMargin == null || pageMargin >= 0);

  /// The session whose latest document is displayed.
  final TypstSession session;

  /// An optional document snapshot to display instead of following
  /// [session.documents]. This lets a host stage a newly compiled document
  /// (for example, until an embedded surface has prepared its first raster)
  /// before exposing it to Flutter's layout.
  final TypstDocument? document;

  /// A decoded first-page preview that is ready to paint for [document].
  ///
  /// The viewer takes ownership of this image. This is intended for a host
  /// that stages a document before making it visible; ordinary viewers should
  /// leave it null and rasterization remains fully automatic.
  final ui.Image? initialPreviewImage;

  /// Pixels per Typst point in [initialPreviewImage]. Required when providing
  /// an initial preview image.
  final double? initialPreviewScale;

  /// End-to-end time that produced [initialPreviewImage], for diagnostics.
  final Duration initialPreviewRenderTime;

  /// Optional controller for programmatic scrolling/zooming.
  final TypstViewerController? controller;

  /// Space around the document canvas in Typst points.
  ///
  /// When set, this overrides [TypstViewerParams.margin]. Keeping it null
  /// preserves the value in [params].
  final double? pageMargin;

  /// Visual and behavioral configuration.
  final TypstViewerParams params;

  @override
  State<TypstViewer> createState() => _TypstViewerState();
}

class _TypstViewerState extends State<TypstViewer>
    with TickerProviderStateMixin {
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
  // Which handle is being dragged, and where (view coordinates) — non-null
  // only for the duration of that drag, so the magnifier shows exactly
  // while (and where) a handle is actually being moved. See
  // _buildSelectionOverlay/_onHandleDrag.
  bool? _draggingHandleIsStart;
  Offset? _handleDragPoint;
  // The endpoint NOT being dragged, captured once when the drag starts, and
  // the endpoint currently under the finger, updated every frame — see
  // _onHandleDrag for why these (rather than re-deriving from
  // _normalizedSelection each frame) are what keep dragging one handle past
  // the other from corrupting the selection.
  _SelPoint? _handleDragFixedEnd;
  _SelPoint? _handleDragMovingPoint;
  // The (view-space) offset from wherever the finger first touched down to
  // the handle's actual text-edge anchor point, captured once at drag start
  // — see _onHandleDrag for why every later frame re-adds this rather than
  // hit-testing the raw finger position directly.
  Offset? _handleDragGrabOffset;

  // Touch pan/pinch-zoom gesture state (see _onGestureScale*).
  double? _gestureStartZoom;
  Offset? _gestureReferenceFocalPoint;
  // Last focal point seen during the gesture — kept for _startZoomSnapBack,
  // since (unlike pan velocity) ScaleEndDetails carries no focal point of
  // its own for the snap-back animation to pin.
  Offset? _lastLocalFocalPoint;

  // Post-release momentum/snap-back (see _startPanFling and
  // _startZoomSnapBack below) — each drives _txController directly, same
  // as a live gesture would.
  AnimationController? _panFlingController;
  AnimationController? _zoomSnapBackController;

  @override
  void initState() {
    super.initState();
    _cache = TypstPageImageCache(
      maxBytes: widget.params.maxImageCacheBytes,
      backgroundColor: widget.params.rasterBackgroundColor,
    );
    // A host-controlled surface such as TypstPageView pins min/max to the
    // same scale. Start there before the first paint; waiting for
    // LayoutBuilder's post-frame fit would briefly paint a newly staged
    // raster at identity scale whenever that fixed scale is not 1.0.
    if (widget.params.minScale == widget.params.maxScale) {
      final scale = widget.params.minScale;
      _txController.value = Matrix4.identity()
        ..scaleByDouble(scale, scale, scale, 1);
    }
    widget.controller?._attach(this);
    _txController.addListener(_onMatrixChanged);
    if (widget.document == null) {
      _subscription = widget.session.documents.listen(_onDocument);
    }
    final initial = widget.document ?? widget.session.document;
    if (initial != null) _onDocument(initial);
    final preview = widget.initialPreviewImage;
    if (preview != null && widget.document != null && initial != null) {
      _cache.seedPreview(
        pageNumber: 1,
        generation: initial.generation,
        image: preview,
        scale: widget.initialPreviewScale ?? _previewScale,
        renderTime: widget.initialPreviewRenderTime,
      );
    }
  }

  @override
  void didUpdateWidget(TypstViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
    if (oldWidget.session != widget.session ||
        oldWidget.document != widget.document) {
      _subscription?.cancel();
      _subscription = null;
      _document = null;
      _layout = null;
      _fitDone = false;
      if (widget.document == null) {
        _subscription = widget.session.documents.listen(_onDocument);
      }
      final initial = widget.document ?? widget.session.document;
      if (initial != null) _onDocument(initial);
    }
    if (_effectivePageMargin(oldWidget) != _effectivePageMargin(widget)) {
      final document = _document;
      if (document != null) _layout = _layoutPages(document);
      _fitDone = false;
      // Unlike the minScale/maxScale branch below, a margin change doesn't
      // necessarily also change the viewport size — the only other trigger
      // for _fitInitialView (see the LayoutBuilder in build()) — so without
      // this, _fitDone would sit false with nothing left to clear it until
      // an unrelated resize happened to come along.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitInitialView();
        _scheduleRender();
      });
    }
    if (oldWidget.params.minScale != widget.params.minScale ||
        oldWidget.params.maxScale != widget.params.maxScale) {
      _fitDone = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitInitialView();
        _scheduleRender();
      });
    }
    if (oldWidget.params.rasterBackgroundColor !=
        widget.params.rasterBackgroundColor) {
      // Already-cached previews/tiles have the old color baked into their
      // pixels (see TypstPageImageCache.renderPreview/renderTile) — merely
      // pointing the cache at the new color wouldn't touch them.
      _cache.backgroundColor = widget.params.rasterBackgroundColor;
      _cache.clear();
      _scheduleRender();
    }
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    _subscription?.cancel();
    widget.controller?._detach();
    _txController.removeListener(_onMatrixChanged);
    _txController.dispose();
    _panFlingController?.dispose();
    _zoomSnapBackController?.dispose();
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
    final margin = _effectivePageMargin(widget);
    var maxWidth = 0.0;
    for (final page in document.pages) {
      maxWidth = math.max(maxWidth, page.width);
    }
    final docWidth = maxWidth + margin * 2;
    final rects = <Rect>[];
    var top = margin;
    for (final page in document.pages) {
      rects.add(
        Rect.fromLTWH(
          (docWidth - page.width) / 2,
          top,
          page.width,
          page.height,
        ),
      );
      top += page.height + margin;
    }
    return TypstPageLayout(pageRects: rects, documentSize: Size(docWidth, top));
  }

  static double _effectivePageMargin(TypstViewer viewer) =>
      viewer.pageMargin ?? viewer.params.margin;

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

  /// The rasterization scale (pixels per point) of the sharpest image
  /// currently painted for the current page: the hi-res tile's scale if one
  /// is cached, otherwise the whole-page preview's scale, otherwise the
  /// current zoom (before anything has rendered).
  double get _currentRasterScale {
    final generation = _document?.generation ?? 0;
    final pageNumber = _currentPageNumber;
    if (pageNumber == 0) return _currentZoom;
    return _cache.tileOf(pageNumber, generation)?.scale ??
        _cache.previewOf(pageNumber)?.scale ??
        _currentZoom;
  }

  void _onMatrixChanged() {
    _scheduleRender();
  }

  /// Repaint request from the selection/link layer.
  void _repaint() {
    if (mounted) setState(() {});
  }

  void _selectionChanged() {
    final selection = _publicSelection;
    widget.params.onSelectionChanged?.call(selection);
    widget.controller?._notifySelectionChanged();
    _repaint();
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
    final focal = focalPoint ?? Offset(viewSize.width / 2, viewSize.height / 2);
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
    // A new touch always takes over from whatever momentum was still
    // running — matches InteractiveViewer's own _onScaleStart.
    _panFlingController?.stop();
    _zoomSnapBackController?.stop();
    _lastGestureScale = 1.0;
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
    _lastLocalFocalPoint = details.localFocalPoint;

    final desiredZoom = startZoom * details.scale;
    final allowedZoom = _elasticZoom(desiredZoom, details.scale);
    final scaleChange = _currentZoom == 0 ? 1.0 : allowedZoom / _currentZoom;
    _applyScaleKeepingScenePointFixed(
      scaleChange,
      referenceFocalPoint,
      details.localFocalPoint,
    );
  }

  void _onGestureScaleEnd(ScaleEndDetails details) {
    _gestureStartZoom = null;
    _gestureReferenceFocalPoint = null;
    _txController.value = _clampMatrix(_txController.value);
    // A snap-back animation already keeps the view sensibly positioned as
    // it springs the zoom back into range — stacking pan momentum on top
    // of that would just fight it, so it's skipped for this release.
    if (!_startZoomSnapBack()) {
      _startPanFling(details.velocity);
    }
  }

  // ---- elastic zoom bounds ----
  //
  // A pinch is allowed to push the zoom slightly past minScale/maxScale,
  // with resistance that increases the further past the limit it goes,
  // springing back smoothly once released — the same rubber-band feel
  // Flutter's own BouncingScrollPhysics gives a scroll view at its edges,
  // reused here by treating the zoom factor as if it were a scroll
  // position between minScale and maxScale. Panning itself stays
  // hard-clamped, as before: only the zoom bound requested this, and
  // stretch-panning past the document edge wasn't part of the ask.
  static const _zoomBoundsPhysics = BouncingScrollPhysics();

  // details.scale as of the previous _onGestureScaleUpdate call this
  // gesture — see _elasticZoom for why the incremental change since then,
  // not the gesture's cumulative change from its start, is what physics
  // gets applied to.
  double _lastGestureScale = 1.0;

  // BouncingScrollPhysics's spring and tolerance constants are tuned for
  // scroll positions in logical pixels (its own default tolerance alone is
  // ~1 full pixel) — feeding it a bare zoom factor (typically 0.05-8.0)
  // makes every one of our distances read as "already within tolerance",
  // so createBallisticSimulation reports "done" before it's animated
  // anything at all (confirmed live: a pinch stretched to 0.44 against a
  // 0.5 minimum sprang back in a single frame, not a visible motion).
  // pdfrx's own InteractiveViewer fork works around exactly this by
  // multiplying scale by a "content width" before handing it to
  // ScrollPhysics; this does the same with the viewport width — any
  // pixel-scale stand-in works, since only its rough order of magnitude
  // matters here, not its exact value.
  double get _zoomMetricScale => math.max(_viewSize?.width ?? 1.0, 1.0);

  ScrollMetrics _zoomMetrics(double zoomInPixelUnits) => FixedScrollMetrics(
    pixels: zoomInPixelUnits,
    minScrollExtent: widget.params.minScale * _zoomMetricScale,
    maxScrollExtent: widget.params.maxScale * _zoomMetricScale,
    viewportDimension:
        (widget.params.maxScale - widget.params.minScale) * _zoomMetricScale,
    axisDirection: AxisDirection.right,
    devicePixelRatio: 1.0,
  );

  // The zoom this frame is actually allowed to reach, given [desiredZoom]
  // (this frame's unclamped target) and [gestureScale] (details.scale,
  // the pinch's cumulative scale change since the gesture started).
  double _elasticZoom(double desiredZoom, double gestureScale) {
    final minScale = widget.params.minScale;
    final maxScale = widget.params.maxScale;
    if (desiredZoom >= minScale && desiredZoom <= maxScale) {
      _lastGestureScale = gestureScale;
      return desiredZoom;
    }
    // Only this frame's own incremental change gets physics applied to it
    // — applying it to the gesture's cumulative change instead would make
    // the resistance depend on how long the gesture has been going, not
    // on how far past the limit the zoom already is (which is what
    // ScrollPosition itself does for each incremental drag update).
    final scaleRatio = _lastGestureScale == 0
        ? 1.0
        : gestureScale / _lastGestureScale;
    _lastGestureScale = gestureScale;
    final scale = _zoomMetricScale;
    final delta = (_currentZoom * scaleRatio - _currentZoom) * scale;
    if (delta == 0) return _currentZoom;
    final damped = _zoomBoundsPhysics.applyPhysicsToUserOffset(
      _zoomMetrics(_currentZoom * scale),
      delta,
    );
    return _currentZoom + damped / scale;
  }

  /// Springs the zoom back to [TypstViewerParams.minScale]/`maxScale` if
  /// the elastic overshoot above left it outside that range — same
  /// physics as [_elasticZoom], via [BouncingScrollPhysics
  /// .createBallisticSimulation]'s own spring, rather than a hand-picked
  /// curve. Returns whether an animation was actually started.
  bool _startZoomSnapBack() {
    final zoom = _currentZoom;
    final minScale = widget.params.minScale;
    final maxScale = widget.params.maxScale;
    if (zoom >= minScale && zoom <= maxScale) return false;

    final scale = _zoomMetricScale;
    final simulation = _zoomBoundsPhysics.createBallisticSimulation(
      _zoomMetrics(zoom * scale),
      0,
    );
    if (simulation == null) return false;

    final viewSize = _viewSize;
    final focalPoint =
        _lastLocalFocalPoint ??
        (viewSize == null
            ? Offset.zero
            : Offset(viewSize.width / 2, viewSize.height / 2));

    final controller = AnimationController.unbounded(vsync: this);
    _zoomSnapBackController?.dispose();
    _zoomSnapBackController = controller;
    controller.addListener(() {
      final referenceScenePoint = MatrixUtils.transformPoint(
        Matrix4.inverted(_txController.value),
        focalPoint,
      );
      // controller.value is in the same pixel-scaled units the simulation
      // was built with (see _zoomMetricScale) — back to a plain zoom
      // factor before treating it as one.
      final desiredZoom = controller.value / scale;
      final scaleChange = _currentZoom == 0 ? 1.0 : desiredZoom / _currentZoom;
      _applyScaleKeepingScenePointFixed(
        scaleChange,
        referenceScenePoint,
        focalPoint,
      );
    });
    controller.animateWith(simulation);
    return true;
  }

  // Scales the current matrix by [scaleChange] around [localFocalPoint],
  // keeping [referenceScenePoint] (a document-space point, read from the
  // matrix *before* this scale) pinned under that same screen point
  // afterward — shared by a live pinch update and the scale-fling tick
  // below, which is really just this same per-frame update run
  // automatically instead of from a finger.
  void _applyScaleKeepingScenePointFixed(
    double scaleChange,
    Offset referenceScenePoint,
    Offset localFocalPoint,
  ) {
    final matrix = _txController.value.clone();
    if (scaleChange != 1.0) {
      matrix.scaleByDouble(scaleChange, scaleChange, scaleChange, 1);
    }
    final focalPointScene = MatrixUtils.transformPoint(
      Matrix4.inverted(matrix),
      localFocalPoint,
    );
    final translation = focalPointScene - referenceScenePoint;
    matrix.translateByDouble(translation.dx, translation.dy, 0, 1);
    _txController.value = _clampMatrix(matrix);
  }

  // Friction coefficient for both fling animations below — Flutter's own
  // InteractiveViewer default (_kDrag), picked for a well-tested feel
  // rather than anything specific to this viewer.
  static const _flingFriction = 0.0000135;

  // Given a velocity and drag, the time at which a FrictionSimulation
  // effectively stops — ported from InteractiveViewer's own (private)
  // _getFinalTime, needed here for the same reason it exists there: sizing
  // the AnimationController's duration to the simulation it's approximating.
  static double _flingFinalTime(
    double velocity,
    double drag, {
    double effectivelyMotionless = 10,
  }) {
    return math.log(effectivelyMotionless / velocity) / math.log(drag / 100);
  }

  /// Continues panning after the finger lifts, decelerating smoothly to a
  /// stop instead of the view halting the instant contact ends — mirrors
  /// InteractiveViewer's own inertia animation, adapted to update
  /// [_txController] (and go through [_clampMatrix]) directly rather than
  /// its private transform helpers. Below [kMinFlingVelocity] (a slow or
  /// stationary release), does nothing — no perceptible motion to continue.
  void _startPanFling(Velocity velocity) {
    if (velocity.pixelsPerSecond.distance < kMinFlingVelocity) return;
    final translation = _txController.value.getTranslation();
    final start = Offset(translation.x, translation.y);
    final frictionX = FrictionSimulation(
      _flingFriction,
      start.dx,
      velocity.pixelsPerSecond.dx,
    );
    final frictionY = FrictionSimulation(
      _flingFriction,
      start.dy,
      velocity.pixelsPerSecond.dy,
    );
    final tFinal = _flingFinalTime(
      velocity.pixelsPerSecond.distance,
      _flingFriction,
    );
    if (!tFinal.isFinite || tFinal <= 0) return;

    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (tFinal * 1000).round().clamp(1, 10000)),
    );
    final animation = Tween<Offset>(
      begin: start,
      end: Offset(frictionX.finalX, frictionY.finalX),
    ).animate(CurvedAnimation(parent: controller, curve: Curves.decelerate));

    _panFlingController?.dispose();
    _panFlingController = controller;
    animation.addListener(() {
      // The matrix's stored translation (unlike a document-space offset)
      // is already in view pixels — see _clampMatrix, which reads/writes
      // it directly the same way — so the animated value can be written
      // straight in, no scale conversion needed. Applied unconditionally
      // (not gated on controller.isAnimating): the very notification that
      // carries the fling's final resting value can arrive already
      // reporting AnimationStatus.completed, particularly when a frame's
      // delta covers the animation's remaining duration in one step —
      // skipping that update would leave the view short of where the
      // fling was actually headed.
      final matrix = _txController.value.clone();
      matrix.storage[12] = animation.value.dx;
      matrix.storage[13] = animation.value.dy;
      // A boundary reached mid-fling isn't a special case: _clampMatrix
      // just holds the position there every subsequent frame while the
      // (now purely notional) animation keeps ticking underneath —
      // equivalent to a hard stop, with no separate handling needed.
      _txController.value = _clampMatrix(matrix);
    });
    controller.forward();
  }

  // ---- rendering pipeline ----

  void _scheduleRender() {
    _renderTimer?.cancel();
    _renderTimer = Timer(widget.params.renderDelay, _updateCachedImages);
  }

  /// Stage one's fixed rasterization scale. The preview always targets
  /// previewDpi, regardless of current zoom — a fixed baseline (like pdfrx's
  /// onePassRenderingScaleThreshold), not scaled down when zoomed out.
  double get _previewScale =>
      (widget.params.fixedRasterDpi ?? widget.params.previewDpi) /
      _pointsPerInch;

  /// Rungs the adaptive tile DPI snaps up to.
  ///
  /// Zoom is continuous, so the resolution a tile "needs" changes by a hair on
  /// every gesture frame. Cached tiles are only reusable at or above the
  /// requested scale, so an unsnapped ladder invalidates the cache on every
  /// small zoom step and re-renders continuously through a pinch. Snapping to
  /// rungs makes a whole range of zooms reuse one tile. Rounding is always
  /// *up*, so a snapped tile is never softer than the zoom asks for — it is at
  /// most one rung sharper than strictly needed.
  static const _tileDpiRungs = <double>[
    72,
    108,
    144,
    216,
    288,
    432,
    576,
    864,
    1152,
  ];

  /// Stage two's zoom-adaptive rasterization scale, capped by maxRenderDpi.
  double get _tileScale {
    final fixedDpi = widget.params.fixedRasterDpi;
    if (fixedDpi != null) return fixedDpi / _pointsPerInch;
    final needed =
        _currentZoom * _devicePixelRatio * widget.params.tileScaleFactor;
    final maxScale = widget.params.maxRenderDpi / _pointsPerInch;
    // Keeps the floor below the ceiling however low maxRenderDpi is set, so
    // the bounds can never invert.
    final floor = math.min(0.5, maxScale);
    for (final rung in _tileDpiRungs) {
      final scale = rung / _pointsPerInch;
      if (scale >= maxScale) break;
      if (scale >= needed) return clampDouble(scale, floor, maxScale);
    }
    return clampDouble(needed, floor, maxScale);
  }

  /// Whether the current zoom needs more resolution than the fixed preview
  /// baseline provides — i.e. whether stage two applies at all right now.
  ///
  /// Tiles outlive the zoom level they were rendered at, so the painter gates
  /// on this rather than on a tile merely existing: without it, zooming back
  /// out would leave a retained hi-res tile painted as a visibly sharper patch
  /// over the middle of an otherwise preview-resolution page.
  bool get _tilesWanted => _tileScale > _previewScale * 1.05;

  Future<void> _updateCachedImages() async {
    final document = _document;
    final layout = _layout;
    if (document == null || layout == null || !mounted) return;

    final visible = _visibleRect;
    final cacheRect = visible.inflate(visible.height / 2);
    final previewScale = _previewScale;

    final visiblePages = <int>{};
    final toRender = <TypstPage>[];
    for (var i = 0; i < layout.pageRects.length; i++) {
      if (!layout.pageRects[i].overlaps(cacheRect)) continue;
      final pageNumber = i + 1;
      visiblePages.add(pageNumber);
      if (!_cache.hasFreshPreview(
        pageNumber,
        previewScale,
        document.generation,
      )) {
        toRender.add(document.pages[i]);
      }
    }

    _cache.evictIfNeeded(visiblePages, _currentPageNumber);

    // Stage two runs *first*: the hi-res tile is the only thing covering what
    // the user is actually looking at, so it must not queue behind a full-page
    // preview for every nearby page. Previews cost ~24ms each at the default
    // previewDpi, so scrolling into a few fresh pages used to stall the visible
    // window for a large fraction of a second before its tile even started.
    // When the current zoom doesn't need a tile, this returns immediately and
    // the previews below are the visible content anyway.
    await _updateTiles(document, layout, visible, previewScale);

    // Nearest pages first, so the page being read is sharp before its
    // neighbours are speculatively filled in.
    final currentPage = _currentPageNumber;
    toRender.sort(
      (a, b) => (a.pageNumber - currentPage).abs().compareTo(
        (b.pageNumber - currentPage).abs(),
      ),
    );
    for (final page in toRender) {
      if (!mounted || _document != document) return;
      await _cache.renderPreview(page, previewScale);
    }

    await _preloadPageText(document, visiblePages);
  }

  /// Renders one high-resolution tile per visible page — the visible window
  /// of the page at the device's true scale — whenever the current zoom
  /// needs more resolution than the preview tier's fixed baseline provides.
  Future<void> _updateTiles(
    TypstDocument document,
    TypstPageLayout layout,
    Rect visible,
    double previewScale,
  ) async {
    final tileScale = _tileScale;
    if (!_tilesWanted) return;

    // A modest margin around the viewport so small pans stay sharp without
    // re-rendering.
    final tileWindow = visible.inflate(visible.shortestSide * 0.15);
    final requests = <(TypstPage, Rect, Rect)>[];
    for (var i = 0; i < layout.pageRects.length; i++) {
      final pageRect = layout.pageRects[i];
      final tileRect = pageRect.intersect(tileWindow);
      if (tileRect.isEmpty) continue;
      final pageNumber = i + 1;
      if (!_cache.hasFreshTile(
        pageNumber,
        tileRect,
        tileScale,
        document.generation,
      )) {
        requests.add((document.pages[i], pageRect, tileRect));
      }
    }
    // Tiles for pages that scrolled away are deliberately *not* dropped here:
    // they stay until the byte budget evicts them (farthest page first), so
    // panning back to a page you were just looking at is instant instead of a
    // fresh render. evictIfNeeded treats them as first-class candidates.

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
                        onPointerSignal: widget.params.enableNavigation
                            ? _onPointerSignal
                            : null,
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
      if (widget.params.enableNavigation)
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
    : super(repaint: Listenable.merge([state._cache, state._txController]));

  final _TypstViewerState state;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = state._layout;
    final document = state._document;
    if (layout == null || document == null) return;

    final visible = state._visibleRect.inflate(state._visibleRect.height / 2);
    final shadow = state.widget.params.pageDropShadow;
    final pageColor = state.widget.params.pageColor;
    final pagePaint = pageColor == null ? null : (Paint()..color = pageColor);

    for (var i = 0; i < layout.pageRects.length; i++) {
      final rect = layout.pageRects[i];
      if (!rect.overlaps(visible)) continue;

      if (shadow != null) {
        canvas.drawRect(
          rect.shift(shadow.offset),
          Paint()
            ..color = shadow.color
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              shadow.blurRadius / 2,
            ),
        );
      }
      if (pagePaint != null) canvas.drawRect(rect, pagePaint);

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

      // Sharp visible-window tile on top of the stretched preview. Gated on
      // the current zoom still wanting stage two — a retained tile from a
      // more zoomed-in state must not paint as a sharper patch once the
      // preview alone is sharp enough.
      final tile = state._tilesWanted
          ? state._cache.tileOf(i + 1, document.generation)
          : null;
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
