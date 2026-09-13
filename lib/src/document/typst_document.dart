import 'dart:typed_data';

import 'typst_page.dart';
import 'typst_session.dart';

/// An immutable snapshot of a successfully compiled document.
///
/// A new snapshot is produced by every successful compilation; older
/// snapshots stop rendering (their pages return null) once they are stale.
class TypstDocument {
  TypstDocument({
    required this.session,
    required this.generation,
    required List<({double width, double height})> pageSizes,
  }) {
    pages = List.unmodifiable([
      for (var i = 0; i < pageSizes.length; i++)
        TypstPage(
          document: this,
          pageNumber: i + 1,
          width: pageSizes[i].width,
          height: pageSizes[i].height,
        ),
    ]);
  }

  /// The session that produced this document.
  final TypstSession session;

  /// Identifies this compilation; newer compilations have higher values.
  final int generation;

  /// The document's pages, in order. The first page is `pages[0]` with
  /// [TypstPage.pageNumber] 1.
  late final List<TypstPage> pages;

  /// Exports this immutable compilation snapshot as vector PDF bytes.
  ///
  /// Throws a stale-document error after the session successfully compiles a
  /// newer document, matching page rendering and structured-text behavior.
  ///
  /// [tagged] controls whether a structure tree describing the document
  /// (used by screen readers and required for PDF/UA) is written. Defaults
  /// to `true`. Pass `false` when exporting an embedded fragment that will
  /// be stamped into another document — its own structure tree wouldn't
  /// describe the final file.
  Future<Uint8List> exportPdf({bool tagged = true}) =>
      session.exportPdf(generation: generation, tagged: tagged);
}
