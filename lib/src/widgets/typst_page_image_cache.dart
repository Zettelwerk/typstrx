import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Color, Rect;

import '../document/typst_page.dart';

/// A cached raster of a whole page at some scale.
class CachedPageImage {
  CachedPageImage({
    required this.image,
    required this.scale,
    required this.generation,
    required this.renderTime,
  });

  final ui.Image image;

  /// Pixels per point the page was rendered at.
  final double scale;

  /// The document generation the image was rendered from.
  final int generation;

  /// Wall-clock time from issuing the render call to having a decoded
  /// [ui.Image] ready (FFI round-trip + Rust rasterization + Dart image
  /// decode).
  final Duration renderTime;

  int get byteSize => image.width * image.height * 4;

  void dispose() => image.dispose();
}

/// A cached raster of the visible window of a page at high resolution.
class CachedPageTile {
  CachedPageTile({
    required this.image,
    required this.rect,
    required this.scale,
    required this.generation,
    required this.renderTime,
  });

  final ui.Image image;

  /// The part of the page the tile covers, in document points.
  final Rect rect;

  /// Pixels per point the tile was rendered at.
  final double scale;

  /// The document generation the tile was rendered from.
  final int generation;

  /// Wall-clock time from issuing the render call to having a decoded
  /// [ui.Image] ready (FFI round-trip + Rust rasterization + Dart image
  /// decode).
  final Duration renderTime;

  int get byteSize => image.width * image.height * 4;

  void dispose() => image.dispose();
}

/// A snapshot of the most recently completed render, for diagnostics/UI
/// (see [TypstViewerController.lastRender]).
class RasterizationMetrics {
  const RasterizationMetrics({
    required this.isTile,
    required this.width,
    required this.height,
    required this.scale,
    required this.renderTime,
  });

  /// Whether this was a hi-res partial tile (`true`) or a whole-page
  /// preview (`false`).
  final bool isTile;

  /// Rendered image width in pixels.
  final int width;

  /// Rendered image height in pixels.
  final int height;

  /// Pixels per point this render was rasterized at.
  final double scale;

  /// [scale] expressed in DPI (dots/pixels per inch) — `scale * 72`.
  double get dpi => scale * 72.0;

  /// Wall-clock render time (FFI + Rust rasterization + Dart image decode).
  final Duration renderTime;

  int get byteSize => width * height * 4;
}

/// Holds rendered page previews and coordinates their (re-)rendering.
///
/// Two tiers per page: a whole-page preview at a capped scale (always
/// available, stretched when stale) and at most one high-resolution tile
/// covering the currently visible window of the page.
///
/// Notifies listeners whenever an image is added or removed so the viewer's
/// painter can repaint.
class TypstPageImageCache extends ChangeNotifier {
  TypstPageImageCache({
    required this.maxBytes,
    this.backgroundColor = const Color(0xffffffff),
  });

  /// Byte budget for all cached images together.
  final int maxBytes;

  /// The color new renders composite against. Mutable (not `final`) so a
  /// runtime change (e.g. [TypstViewerParams.rasterBackgroundColor]
  /// following a theme toggle) takes effect on the next render — call
  /// [clear] alongside setting it, since already-cached images have this
  /// color baked into their pixels and won't pick up the change on their
  /// own.
  Color backgroundColor;

  final _previews = <int, CachedPageImage>{};
  final _tiles = <int, CachedPageTile>{};
  final _rendering = <int, double>{};
  final _renderingTiles = <int, (Rect, double)>{};
  bool _disposed = false;

  /// Metrics for the most recently completed render (preview or tile),
  /// across all pages. Null until the first render completes.
  RasterizationMetrics? get lastRender => _lastRender;
  RasterizationMetrics? _lastRender;

  /// The cached preview for the page, if any (may be stale in scale or
  /// generation — the painter stretches it while a replacement renders).
  CachedPageImage? previewOf(int pageNumber) => _previews[pageNumber];

  /// Whether a preview at (at least) this scale and generation exists.
  bool hasFreshPreview(int pageNumber, double scale, int generation) {
    final cached = _previews[pageNumber];
    if (cached == null || cached.generation != generation) return false;
    // Nearly-equal scale is fine (avoids re-render churn on zoom jitter);
    // zoom-out never triggers a re-render.
    return cached.scale >= scale * 0.95;
  }

  /// Renders a whole-page preview at [scale] unless an equivalent render is
  /// already in flight.
  Future<void> renderPreview(TypstPage page, double scale) async {
    final pageNumber = page.pageNumber;
    final inFlight = _rendering[pageNumber];
    if (inFlight != null && inFlight >= scale * 0.95) return;
    _rendering[pageNumber] = scale;
    final stopwatch = Stopwatch()..start();
    try {
      final image = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        backgroundColor: backgroundColor,
      );
      if (image == null) return; // stale generation — drop silently
      final uiImage = await image.createImage();
      stopwatch.stop();
      if (_disposed) {
        uiImage.dispose();
        return;
      }
      _previews[pageNumber]?.dispose();
      _previews[pageNumber] = CachedPageImage(
        image: uiImage,
        scale: scale,
        generation: page.document.generation,
        renderTime: stopwatch.elapsed,
      );
      _lastRender = RasterizationMetrics(
        isTile: false,
        width: uiImage.width,
        height: uiImage.height,
        scale: scale,
        renderTime: stopwatch.elapsed,
      );
      notifyListeners();
    } finally {
      if (_rendering[pageNumber] == scale) {
        _rendering.remove(pageNumber);
      }
    }
  }

  /// Takes ownership of an already decoded whole-page preview.
  ///
  /// Used by embedded hosts that render a new document before committing its
  /// dimensions to Flutter's layout. The next viewer can therefore paint the
  /// staged preview immediately instead of rasterizing the same page again.
  void seedPreview({
    required int pageNumber,
    required int generation,
    required ui.Image image,
    required double scale,
    required Duration renderTime,
  }) {
    _previews[pageNumber]?.dispose();
    _previews[pageNumber] = CachedPageImage(
      image: image,
      scale: scale,
      generation: generation,
      renderTime: renderTime,
    );
    _lastRender = RasterizationMetrics(
      isTile: false,
      width: image.width,
      height: image.height,
      scale: scale,
      renderTime: renderTime,
    );
  }

  /// The cached high-resolution tile of the page, if its generation matches.
  CachedPageTile? tileOf(int pageNumber, int generation) {
    final tile = _tiles[pageNumber];
    if (tile == null || tile.generation != generation) return null;
    return tile;
  }

  /// Whether a usable tile (covering this window, at least this scale, same
  /// generation) already exists or is being rendered.
  ///
  /// The stored tile only has to *contain* the requested window, not match it
  /// edge-for-edge. Tiles outlive the viewport they were rendered for, and a
  /// pan away and back never reproduces the original rect exactly; an equality
  /// test would miss every time and re-render a tile the cache already holds.
  bool hasFreshTile(int pageNumber, Rect rect, double scale, int generation) {
    bool matches(Rect r, double s) =>
        s >= scale * 0.95 &&
        r.left <= rect.left + 1 &&
        r.top <= rect.top + 1 &&
        r.right >= rect.right - 1 &&
        r.bottom >= rect.bottom - 1;
    final tile = _tiles[pageNumber];
    if (tile != null &&
        tile.generation == generation &&
        matches(tile.rect, tile.scale)) {
      return true;
    }
    final inFlight = _renderingTiles[pageNumber];
    return inFlight != null && matches(inFlight.$1, inFlight.$2);
  }

  /// Renders the window [tileRect] (in document points) of [page] at [scale]
  /// pixels per point. [pageRect] is the page's rect in document points.
  Future<void> renderTile(
    TypstPage page,
    Rect pageRect,
    Rect tileRect,
    double scale,
  ) async {
    final pageNumber = page.pageNumber;
    _renderingTiles[pageNumber] = (tileRect, scale);
    final stopwatch = Stopwatch()..start();
    try {
      final inPage = tileRect.shift(-pageRect.topLeft);
      final image = await page.render(
        x: (inPage.left * scale).floor(),
        y: (inPage.top * scale).floor(),
        width: (inPage.width * scale).ceil(),
        height: (inPage.height * scale).ceil(),
        fullWidth: pageRect.width * scale,
        fullHeight: pageRect.height * scale,
        backgroundColor: backgroundColor,
      );
      if (image == null) return; // stale generation — drop silently
      final uiImage = await image.createImage();
      stopwatch.stop();
      if (_disposed) {
        uiImage.dispose();
        return;
      }
      _tiles[pageNumber]?.dispose();
      _tiles[pageNumber] = CachedPageTile(
        image: uiImage,
        rect: tileRect,
        scale: scale,
        generation: page.document.generation,
        renderTime: stopwatch.elapsed,
      );
      _lastRender = RasterizationMetrics(
        isTile: true,
        width: uiImage.width,
        height: uiImage.height,
        scale: scale,
        renderTime: stopwatch.elapsed,
      );
      notifyListeners();
    } finally {
      if (_renderingTiles[pageNumber] == (tileRect, scale)) {
        _renderingTiles.remove(pageNumber);
      }
    }
  }

  /// Evicts images of pages not in [protectedPages] until the byte budget is
  /// met, farthest from [currentPage] first.
  ///
  /// Tiles are eviction candidates in their own right, not just collateral of
  /// their page's preview: tiles outlive the viewport, so a page can hold a
  /// tile whose preview was already evicted, and keying the candidate list on
  /// previews alone would leave those unreachable and never freed.
  void evictIfNeeded(Set<int> protectedPages, int currentPage) {
    var total = totalBytes;
    if (total <= maxBytes) return;

    final evictable =
        <int>{
            ..._previews.keys,
            ..._tiles.keys,
          }.where((pageNumber) => !protectedPages.contains(pageNumber)).toList()
          ..sort((a, b) => (b - currentPage).abs() - (a - currentPage).abs());
    for (final pageNumber in evictable) {
      if (total <= maxBytes) break;
      final removed = _previews.remove(pageNumber);
      if (removed != null) {
        total -= removed.byteSize;
        removed.dispose();
      }
      final tile = _tiles.remove(pageNumber);
      if (tile != null) {
        total -= tile.byteSize;
        tile.dispose();
      }
    }
    notifyListeners();
  }

  /// Drops cached images for pages beyond [pageCount] — used after a
  /// recompile shrinks the document. Images of surviving page numbers stay
  /// (even from an older generation) until their re-render replaces them, so
  /// typing never flashes blank pages.
  void removePagesAbove(int pageCount) {
    final stalePreviews = _previews.keys
        .where((pageNumber) => pageNumber > pageCount)
        .toList();
    final staleTiles = _tiles.keys
        .where((pageNumber) => pageNumber > pageCount)
        .toList();
    if (stalePreviews.isEmpty && staleTiles.isEmpty) return;
    for (final pageNumber in stalePreviews) {
      _previews.remove(pageNumber)!.dispose();
    }
    for (final pageNumber in staleTiles) {
      _tiles.remove(pageNumber)!.dispose();
    }
    notifyListeners();
  }

  /// Drops every cached image (previews and tiles alike) so the next render
  /// pass starts fresh — for a change that invalidates already-rendered
  /// pixels outright (e.g. [backgroundColor]), rather than just some pages
  /// (see [removePagesAbove]) or the byte budget (see [evictIfNeeded]).
  void clear() {
    for (final entry in _previews.values) {
      entry.dispose();
    }
    _previews.clear();
    for (final tile in _tiles.values) {
      tile.dispose();
    }
    _tiles.clear();
    notifyListeners();
  }

  /// Total bytes currently held.
  int get totalBytes =>
      _previews.values.fold(0, (sum, entry) => sum + entry.byteSize) +
      _tiles.values.fold(0, (sum, tile) => sum + tile.byteSize);

  /// Number of cached images (previews + tiles) currently held.
  int get cachedImageCount => _previews.length + _tiles.length;

  /// Largest distance-sorted page numbers currently cached; for tests.
  @visibleForTesting
  List<int> get cachedPageNumbers => _previews.keys.toList()..sort();

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _previews.values) {
      entry.dispose();
    }
    _previews.clear();
    for (final tile in _tiles.values) {
      tile.dispose();
    }
    _tiles.clear();
    super.dispose();
  }
}
