import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../document/typst_link.dart';

/// Which modifier key makes mouse-wheel scroll zoom a [TypstViewer] instead
/// of panning it. See [TypstViewerParams.wheelZoomTrigger].
enum WheelZoomTrigger {
  /// Wheel scroll zooms while Control is held; otherwise it pans. The
  /// default — matches most viewers, editors, and browsers.
  control,

  /// Wheel scroll zooms while Shift is held; otherwise it pans.
  shift,

  /// Wheel scroll zooms while Alt is held; otherwise it pans.
  alt,

  /// Wheel scroll always zooms; it never pans.
  always,

  /// Wheel scroll never zooms; it always pans.
  never,
}

/// Configuration for [TypstViewer].
class TypstViewerParams {
  const TypstViewerParams({
    this.margin = 8.0,
    this.minScale = 0.25,
    this.maxScale = 8.0,
    this.maxRenderScale = 4.0,
    this.previewScaleCap = 2.0,
    this.maxImageCacheBytes = 100 * 1024 * 1024,
    this.renderDelay = const Duration(milliseconds: 80),
    this.backgroundColor = const Color(0xffdddddd),
    this.pageDropShadow = const BoxShadow(
      color: Color(0x40000000),
      blurRadius: 4,
      offset: Offset(1, 2),
    ),
    this.enableTextSelection = true,
    this.selectionColor = const Color(0x553b82f6),
    this.onLinkTap,
    this.wheelZoomTrigger = WheelZoomTrigger.control,
    this.shouldZoomOnWheelScroll,
  });

  /// Space between and around pages, in points (= logical pixels at zoom 1).
  final double margin;

  /// Minimum zoom.
  final double minScale;

  /// Maximum zoom.
  final double maxScale;

  /// Upper bound for the rasterization scale (pixels per point) of high-
  /// resolution page tiles. Values beyond ~4 rarely improve visible quality
  /// but grow render cost and memory quadratically.
  final double maxRenderScale;

  /// Upper bound for the rasterization scale of whole-page preview images.
  /// The preview tier keeps every visible page legible; the tile tier
  /// provides full sharpness for the visible window when zoomed in further.
  final double previewScaleCap;

  /// Byte budget for cached page images. Pages farthest from the current
  /// viewport are evicted first when the budget is exceeded.
  final int maxImageCacheBytes;

  /// How long the viewer waits after scrolling/zooming stops changing before
  /// (re)rendering page images.
  final Duration renderDelay;

  /// Color painted around and between pages.
  final Color backgroundColor;

  /// Drop shadow painted under every page; null for none.
  final BoxShadow? pageDropShadow;

  /// Whether text can be selected (mouse drag / long-press) and copied.
  final bool enableTextSelection;

  /// Fill color of the selection highlight.
  final Color selectionColor;

  /// Called when a link is tapped. Internal links (with a
  /// [TypstLink.dest]) additionally navigate within the viewer by default;
  /// URL links only invoke this callback (wire it to e.g. `url_launcher`).
  final void Function(TypstLink link)? onLinkTap;

  /// Which modifier key toggles mouse-wheel scroll between panning and
  /// zooming. Ignored when [shouldZoomOnWheelScroll] is set.
  final WheelZoomTrigger wheelZoomTrigger;

  /// Overrides [wheelZoomTrigger] with custom logic: return true to zoom on
  /// a given wheel scroll event, false to pan. Use this for triggers other
  /// than a single modifier key (e.g. always requiring both Control and
  /// Shift, or basing it on [PointerScrollEvent.device]).
  final bool Function(PointerScrollEvent event)? shouldZoomOnWheelScroll;
}
