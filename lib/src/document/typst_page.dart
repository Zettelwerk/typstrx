import 'dart:ui';

import '../rust/api/types.dart' as rust;
import 'typst_document.dart';
import 'typst_image.dart';

/// A single page of a compiled [TypstDocument].
class TypstPage {
  TypstPage({
    required this.document,
    required this.pageNumber,
    required this.width,
    required this.height,
  });

  /// The document this page belongs to.
  final TypstDocument document;

  /// Page number; the first page is 1.
  final int pageNumber;

  /// Page width in typographic points (1/72 inch).
  final double width;

  /// Page height in typographic points (1/72 inch).
  final double height;

  /// Renders a sub-area or the full page.
  ///
  /// [x], [y], [width], [height] select the window to render, in pixels, out
  /// of the page rasterized at a virtual full size of [fullWidth] x
  /// [fullHeight] pixels.
  /// - If [width]/[height] are omitted, [fullWidth]/[fullHeight] are used
  ///   (i.e. the whole page is rendered).
  /// - If [fullWidth]/[fullHeight] are omitted, the page's size in points is
  ///   used (72 dpi).
  ///
  /// [backgroundColor] fills the tile before the page is composited onto it;
  /// it is forced opaque.
  ///
  /// Returns null when the document has been replaced by a newer compilation
  /// (the render would be stale) — callers should simply drop the request.
  Future<TypstImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color backgroundColor = const Color(0xffffffff),
  }) async {
    final fullW = (fullWidth ?? this.width).round();
    final fullH = (fullHeight ?? this.height).round();
    final w = width ?? fullW;
    final h = height ?? fullH;
    try {
      final region = await document.session.renderPageRegion(
        generation: document.generation,
        pageIndex: pageNumber - 1,
        x: x,
        y: y,
        width: w,
        height: h,
        fullWidth: fullW,
        fullHeight: fullH,
        backgroundArgb: backgroundColor.toARGB32(),
      );
      return TypstImage(
        width: region.width,
        height: region.height,
        pixels: region.pixels,
      );
    } on rust.TypstrxError_Stale {
      return null;
    } on rust.TypstrxError_NoDocument {
      return null;
    }
  }
}
