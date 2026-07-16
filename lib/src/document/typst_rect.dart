import 'dart:ui';

import '../rust/api/types.dart' as rust;

/// A rectangle in page coordinates: typographic points, top-left origin,
/// y-down. Matches both Typst's and Flutter's coordinate conventions, so
/// conversion to screen space is a pure scale + translate.
class TypstRect {
  const TypstRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  static const TypstRect empty = TypstRect(0, 0, 0, 0);

  double get width => right - left;
  double get height => bottom - top;
  bool get isEmpty => left >= right || top >= bottom;

  /// As a Flutter [Rect] in page points.
  Rect toRect() => Rect.fromLTRB(left, top, right, bottom);

  /// As a [Rect] in document coordinates given the page's rect in the
  /// document layout.
  Rect toRectInDocument(Rect pageRect) => Rect.fromLTRB(
        pageRect.left + left,
        pageRect.top + top,
        pageRect.left + right,
        pageRect.top + bottom,
      );

  bool containsPoint(Offset point, {double margin = 0}) =>
      point.dx >= left - margin &&
      point.dx <= right + margin &&
      point.dy >= top - margin &&
      point.dy <= bottom + margin;

  TypstRect merge(TypstRect other) => TypstRect(
        left < other.left ? left : other.left,
        top < other.top ? top : other.top,
        right > other.right ? right : other.right,
        bottom > other.bottom ? bottom : other.bottom,
      );

  @override
  String toString() => 'TypstRect($left, $top, $right, $bottom)';

  /// Converts a bridge-level rect.
  static TypstRect fromRust(rust.RectPt rect) =>
      TypstRect(rect.left, rect.top, rect.right, rect.bottom);
}
