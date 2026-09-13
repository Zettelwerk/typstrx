import 'typst_rect.dart';

/// The text of a page with per-character geometry.
///
/// [fullText] is the page's text in visual reading order with `\n` between
/// lines. [charRects] holds one rect per UTF-16 code unit of [fullText], so
/// any Dart string index maps directly onto page geometry.
class TypstPageText {
  const TypstPageText({
    required this.pageNumber,
    required this.fullText,
    required this.charRects,
    required this.fragments,
  });

  /// Page number; the first page is 1.
  final int pageNumber;

  /// The page's text in visual reading order.
  final String fullText;

  /// One bounding rect (page points) per UTF-16 code unit of [fullText].
  final List<TypstRect> charRects;

  /// Consecutive runs of [fullText]; fragments cover the entire text.
  final List<TypstPageTextFragment> fragments;

  /// The index of the character whose rect contains (or is nearest to)
  /// [point] within [tolerance], or -1.
  int getCharIndexAt(double x, double y, {double tolerance = 4}) {
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < charRects.length; i++) {
      final rect = charRects[i];
      if (rect.isEmpty) continue;
      if (y < rect.top - tolerance || y > rect.bottom + tolerance) continue;
      final dx = x < rect.left
          ? rect.left - x
          : x > rect.right
          ? x - rect.right
          : 0.0;
      final dy = y < rect.top
          ? rect.top - y
          : y > rect.bottom
          ? y - rect.bottom
          : 0.0;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
      if (distance == 0) break;
    }
    if (best >= 0 && bestDistance > tolerance * tolerance * 100) return -1;
    return best;
  }

  /// Word range (start inclusive, end exclusive) around [index].
  (int, int) wordBoundaryAt(int index) {
    if (fullText.isEmpty) return (0, 0);
    final clamped = index.clamp(0, fullText.length - 1);
    bool isWordChar(int i) {
      final c = fullText[i];
      return c.trim().isNotEmpty && c != '\n';
    }

    if (!isWordChar(clamped)) return (clamped, clamped + 1);
    var start = clamped;
    while (start > 0 && isWordChar(start - 1)) {
      start--;
    }
    var end = clamped + 1;
    while (end < fullText.length && isWordChar(end)) {
      end++;
    }
    return (start, end);
  }

  /// Merged highlight rects (page points) for the text range
  /// [start, end) — one rect per line.
  List<TypstRect> rectsForRange(int start, int end) {
    final rects = <TypstRect>[];
    TypstRect? current;
    for (var i = start; i < end && i < charRects.length; i++) {
      final rect = charRects[i];
      if (rect.isEmpty) continue;
      if (current == null) {
        current = rect;
      } else if (rect.top < current.bottom && rect.bottom > current.top) {
        current = current.merge(rect);
      } else {
        rects.add(current);
        current = rect;
      }
    }
    if (current != null) rects.add(current);
    return rects;
  }
}

/// A run of text on a page: `pageText.fullText[index..index + length]`.
class TypstPageTextFragment {
  const TypstPageTextFragment({
    required this.pageText,
    required this.index,
    required this.length,
    required this.bounds,
  });

  /// The page text this fragment belongs to.
  final TypstPageText pageText;

  /// Start index in [TypstPageText.fullText] (UTF-16 code units).
  final int index;

  /// Length in UTF-16 code units.
  final int length;

  /// Bounding box of the fragment in page points.
  final TypstRect bounds;

  /// The fragment's text.
  String get text => pageText.fullText.substring(index, index + length);
}
