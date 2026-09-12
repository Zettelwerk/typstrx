import 'dart:ui';

import 'package:flutter/foundation.dart';

/// One endpoint in a rendered Typst text selection.
class TypstTextPosition {
  const TypstTextPosition({required this.pageNumber, required this.offset});

  /// One-based page number.
  final int pageNumber;

  /// UTF-16 offset into that page's [TypstPageText.fullText].
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is TypstTextPosition &&
      other.pageNumber == pageNumber &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(pageNumber, offset);
}

/// A selected rectangle in page-local Typst points.
class TypstTextSelectionRect {
  const TypstTextSelectionRect({required this.pageNumber, required this.rect});

  final int pageNumber;
  final Rect rect;

  @override
  bool operator ==(Object other) =>
      other is TypstTextSelectionRect &&
      other.pageNumber == pageNumber &&
      other.rect == rect;

  @override
  int get hashCode => Object.hash(pageNumber, rect);
}

/// Host-facing snapshot of the current rendered-text selection.
class TypstTextSelection {
  const TypstTextSelection({
    required this.start,
    required this.end,
    required this.text,
    required this.rects,
  });

  final TypstTextPosition start;
  final TypstTextPosition end;
  final String text;
  final List<TypstTextSelectionRect> rects;

  @override
  bool operator ==(Object other) =>
      other is TypstTextSelection &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      listEquals(other.rects, rects);

  @override
  int get hashCode => Object.hash(start, end, text, Object.hashAll(rects));
}
