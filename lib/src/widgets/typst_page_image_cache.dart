import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Rect;

import '../document/typst_page.dart';

/// A cached raster of a whole page at some scale.
class CachedPageImage {
  CachedPageImage({
    required this.image,
    required this.scale,
    required this.generation,
  });

  final ui.Image image;

  /// Pixels per point the page was rendered at.
  final double scale;

  /// The document generation the image was rendered from.
  final int generation;

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
  });

  final ui.Image image;

  /// The part of the page the tile covers, in document points.
  final Rect rect;

  /// Pixels per point the tile was rendered at.
  final double scale;

  /// The document generation the tile was rendered from.
  final int generation;

  int get byteSize => image.width * image.height * 4;

  void dispose() => image.dispose();
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
  TypstPageImageCache({required this.maxBytes});

  /// Byte budget for all cached images together.
  final int maxBytes;

  final _previews = <int, CachedPageImage>{};
  final _tiles = <int, CachedPageTile>{};
  final _rendering = <int, double>{};
  final _renderingTiles = <int, (Rect, double)>{};
  bool _disposed = false;

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
    try {
      final image = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      if (image == null) return; // stale generation — drop silently
      final uiImage = await image.createImage();
      if (_disposed) {
        uiImage.dispose();
        return;
      }
      _previews[pageNumber]?.dispose();
      _previews[pageNumber] = CachedPageImage(
        image: uiImage,
        scale: scale,
        generation: page.document.generation,
      );
      notifyListeners();
    } finally {
      if (_rendering[pageNumber] == scale) {
        _rendering.remove(pageNumber);
      }
    }
  }

  /// The cached high-resolution tile of the page, if its generation matches.
  CachedPageTile? tileOf(int pageNumber, int generation) {
    final tile = _tiles[pageNumber];
    if (tile == null || tile.generation != generation) return null;
    return tile;
  }

  /// Whether an equivalent tile (same window, at least this scale, same
  /// generation) already exists or is being rendered.
  bool hasFreshTile(int pageNumber, Rect rect, double scale, int generation) {
    bool matches(Rect r, double s) =>
        s >= scale * 0.95 &&
        (r.left - rect.left).abs() < 1 &&
        (r.top - rect.top).abs() < 1 &&
        (r.right - rect.right).abs() < 1 &&
        (r.bottom - rect.bottom).abs() < 1;
    final tile = _tiles[pageNumber];
    if (tile != null && tile.generation == generation && matches(tile.rect, tile.scale)) {
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
    try {
      final inPage = tileRect.shift(-pageRect.topLeft);
      final image = await page.render(
        x: (inPage.left * scale).floor(),
        y: (inPage.top * scale).floor(),
        width: (inPage.width * scale).ceil(),
        height: (inPage.height * scale).ceil(),
        fullWidth: pageRect.width * scale,
        fullHeight: pageRect.height * scale,
      );
      if (image == null) return; // stale generation — drop silently
      final uiImage = await image.createImage();
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
      );
      notifyListeners();
    } finally {
      if (_renderingTiles[pageNumber] == (tileRect, scale)) {
        _renderingTiles.remove(pageNumber);
      }
    }
  }

  /// Drops high-resolution tiles for pages not in [keep] (or all when zoomed
  /// back out far enough that the preview suffices).
  void pruneTiles({required Set<int> keep}) {
    final stale =
        _tiles.keys.where((pageNumber) => !keep.contains(pageNumber)).toList();
    if (stale.isEmpty) return;
    for (final pageNumber in stale) {
      _tiles.remove(pageNumber)!.dispose();
    }
    notifyListeners();
  }

  /// Evicts images of pages not in [protectedPages] until the byte budget is
  /// met, farthest from [currentPage] first.
  void evictIfNeeded(Set<int> protectedPages, int currentPage) {
    var total = totalBytes;
    if (total <= maxBytes) return;

    final evictable = _previews.keys
        .where((pageNumber) => !protectedPages.contains(pageNumber))
        .toList()
      ..sort((a, b) => (b - currentPage).abs() - (a - currentPage).abs());
    for (final pageNumber in evictable) {
      if (total <= maxBytes) break;
      final removed = _previews.remove(pageNumber)!;
      total -= removed.byteSize;
      removed.dispose();
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
    final stalePreviews =
        _previews.keys.where((pageNumber) => pageNumber > pageCount).toList();
    final staleTiles =
        _tiles.keys.where((pageNumber) => pageNumber > pageCount).toList();
    if (stalePreviews.isEmpty && staleTiles.isEmpty) return;
    for (final pageNumber in stalePreviews) {
      _previews.remove(pageNumber)!.dispose();
    }
    for (final pageNumber in staleTiles) {
      _tiles.remove(pageNumber)!.dispose();
    }
    notifyListeners();
  }

  /// Total bytes currently held.
  int get totalBytes =>
      _previews.values.fold(0, (sum, entry) => sum + entry.byteSize) +
      _tiles.values.fold(0, (sum, tile) => sum + tile.byteSize);

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

