import 'package:flutter/widgets.dart';

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
}
