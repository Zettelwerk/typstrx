import 'typst_rect.dart';

/// The target of an internal link: a position on a page.
class TypstDest {
  const TypstDest({required this.pageNumber, this.x, this.y});

  /// Target page; the first page is 1.
  final int pageNumber;

  /// Target x position on the page in points, if known.
  final double? x;

  /// Target y position on the page in points, if known.
  final double? y;
}

/// A tappable link region on a page. Exactly one of [url] and [dest] is set.
class TypstLink {
  const TypstLink({required this.rect, this.url, this.dest});

  /// The link's region in page points.
  final TypstRect rect;

  /// External URL for web links.
  final Uri? url;

  /// Internal destination for document-internal links.
  final TypstDest? dest;
}
