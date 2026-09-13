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
  Future<Uint8List> exportPdf() => session.exportPdf(generation: generation);
}
