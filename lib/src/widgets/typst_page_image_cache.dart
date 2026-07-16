import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

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

/// Holds rendered page previews and coordinates their (re-)rendering.
///
/// Notifies listeners whenever an image is added or removed so the viewer's
/// painter can repaint.
class TypstPageImageCache extends ChangeNotifier {
  TypstPageImageCache({required this.maxBytes});

  /// Byte budget for all cached images together.
  final int maxBytes;

  final _previews = <int, CachedPageImage>{};
  final _rendering = <int, double>{};
  bool _disposed = false;

  /// The cached preview for the page, if any (may be stale in scale or
  /// generation — the painter stretches it while a replacement renders).
  CachedPageImage? previewOf(int pageNumber) => _previews[pageNumber];

  /// Whether a preview at (at least) this scale and generation exists.
  bool hasFreshPreview(int pageNumber, double scale, int generation) {
    final cached = _previews[pageNumber];
    if (cached == null || cached.generation != generation) return false;
    // A slightly smaller scale still looks fine; re-render only on a
    // meaningful zoom-in, and never re-render on zoom-out.
    return cached.scale >= scale * 0.8;
  }

  /// Renders a whole-page preview at [scale] unless an equivalent render is
  /// already in flight.
  Future<void> renderPreview(TypstPage page, double scale) async {
    final pageNumber = page.pageNumber;
    final inFlight = _rendering[pageNumber];
    if (inFlight != null && inFlight >= scale * 0.8) return;
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

  /// Evicts images of pages not in [protectedPages] until the byte budget is
  /// met, farthest from [currentPage] first.
  void evictIfNeeded(Set<int> protectedPages, int currentPage) {
    var total = 0;
    for (final entry in _previews.values) {
      total += entry.byteSize;
    }
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
    }
    notifyListeners();
  }

  /// Drops cached images for pages beyond [pageCount] — used after a
  /// recompile shrinks the document. Images of surviving page numbers stay
  /// (even from an older generation) until their re-render replaces them, so
  /// typing never flashes blank pages.
  void removePagesAbove(int pageCount) {
    final stale =
        _previews.keys.where((pageNumber) => pageNumber > pageCount).toList();
    if (stale.isEmpty) return;
    for (final pageNumber in stale) {
      _previews.remove(pageNumber)!.dispose();
    }
    notifyListeners();
  }

  /// Total bytes currently held.
  int get totalBytes =>
      _previews.values.fold(0, (sum, entry) => sum + entry.byteSize);

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
    super.dispose();
  }
}

