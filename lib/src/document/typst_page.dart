import 'dart:async';
import 'dart:ui';

import '../rust/api/types.dart' as rust;
import 'typst_document.dart';
import 'typst_image.dart';
import 'typst_link.dart';
import 'typst_rect.dart';
import 'typst_text.dart';

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

  Future<TypstPageText?>? _textFuture;

  /// Loads the page's text with per-character geometry (cached per page).
  ///
  /// Returns null when the document has been replaced by a newer compilation.
  Future<TypstPageText?> loadStructuredText() {
    return _textFuture ??= _loadText();
  }

  /// Loads the page's links (cached per page, via the same extraction as
  /// [loadStructuredText]).
  ///
  /// Returns an empty list when the document has become stale.
  Future<List<TypstLink>> loadLinks() async =>
      (await _loadRaw())?.toTypstLinks() ?? const [];

  Future<rust.PageTextData?>? _rawFuture;

  Future<rust.PageTextData?> _loadRaw() {
    return _rawFuture ??= () async {
      try {
        return await document.session.pageText(
          generation: document.generation,
          pageIndex: pageNumber - 1,
        );
      } on rust.TypstrxError_Stale {
        return null;
      } on rust.TypstrxError_NoDocument {
        return null;
      }
    }();
  }

  Future<TypstPageText?> _loadText() async {
    final raw = await _loadRaw();
    if (raw == null) return null;
    final charRects = [
      for (final rect in raw.charRects) TypstRect.fromRust(rect),
    ];
    final fragments = <TypstPageTextFragment>[];
    final pageText = TypstPageText(
      pageNumber: pageNumber,
      fullText: raw.fullText,
      charRects: charRects,
      fragments: fragments,
    );
    for (final fragment in raw.fragments) {
      fragments.add(TypstPageTextFragment(
        pageText: pageText,
        index: fragment.index,
        length: fragment.length,
        bounds: TypstRect.fromRust(fragment.bounds),
      ));
    }
    return pageText;
  }
}

/// Maps bridge-level link data to the public model.
extension on rust.PageTextData {
  List<TypstLink> toTypstLinks() => [
        for (final link in links)
          TypstLink(
            rect: TypstRect.fromRust(link.rect),
            url: link.url != null ? Uri.tryParse(link.url!) : null,
            dest: link.destPage != null
                ? TypstDest(
                    pageNumber: link.destPage!,
                    x: link.destXPt,
                    y: link.destYPt,
                  )
                : null,
          ),
      ];
}
