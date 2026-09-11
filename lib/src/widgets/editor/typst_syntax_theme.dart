import 'package:flutter/widgets.dart';

import '../../document/typst_highlight.dart';

/// Maps [TypstHighlightTag] categories to text styles for
/// [TypstEditorController].
///
/// [TypstSyntaxTheme.defaultTheme] is a reasonable starting point; construct
/// a custom instance, or use [copyWith] to override a handful of categories
/// on top of the default.
@immutable
class TypstSyntaxTheme {
  const TypstSyntaxTheme(this._styles);

  final Map<TypstHighlightTag, TextStyle> _styles;

  /// The style for [tag], or null if this theme doesn't style it (in which
  /// case the editor's base text style applies unchanged).
  TextStyle? styleFor(TypstHighlightTag tag) => _styles[tag];

  /// Returns a copy with [overrides] layered on top of this theme's styles.
  TypstSyntaxTheme copyWith(Map<TypstHighlightTag, TextStyle> overrides) {
    return TypstSyntaxTheme({..._styles, ...overrides});
  }

  /// A legible default palette (loosely modeled on common light-background
  /// code themes). Doesn't set a color for [TypstHighlightTag.error] —
  /// [TypstEditorController] never emits that tag; malformed syntax is
  /// surfaced through compiler diagnostics instead.
  static final TypstSyntaxTheme defaultTheme = TypstSyntaxTheme({
    TypstHighlightTag.comment: const TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic),
    TypstHighlightTag.escape: const TextStyle(color: Color(0xFF22863A)),
    TypstHighlightTag.strong: const TextStyle(fontWeight: FontWeight.bold),
    TypstHighlightTag.emph: const TextStyle(fontStyle: FontStyle.italic),
    TypstHighlightTag.link: const TextStyle(color: Color(0xFF032F62), decoration: TextDecoration.underline),
    TypstHighlightTag.raw: const TextStyle(color: Color(0xFF005CC5)),
    TypstHighlightTag.label: const TextStyle(color: Color(0xFF6F42C1)),
    TypstHighlightTag.ref: const TextStyle(color: Color(0xFF6F42C1)),
    TypstHighlightTag.heading: const TextStyle(color: Color(0xFF005CC5), fontWeight: FontWeight.bold),
    TypstHighlightTag.listMarker: const TextStyle(color: Color(0xFFD73A49)),
    TypstHighlightTag.listTerm: const TextStyle(fontWeight: FontWeight.bold),
    TypstHighlightTag.mathDelimiter: const TextStyle(color: Color(0xFFD73A49)),
    TypstHighlightTag.mathOperator: const TextStyle(color: Color(0xFFD73A49)),
    TypstHighlightTag.keyword: const TextStyle(color: Color(0xFFD73A49), fontWeight: FontWeight.w600),
    TypstHighlightTag.operator_: const TextStyle(color: Color(0xFFD73A49)),
    TypstHighlightTag.number: const TextStyle(color: Color(0xFF005CC5)),
    TypstHighlightTag.string: const TextStyle(color: Color(0xFF032F62)),
    TypstHighlightTag.function: const TextStyle(color: Color(0xFF6F42C1)),
    TypstHighlightTag.interpolated: const TextStyle(color: Color(0xFFE36209)),
  });
}

/// Builds a [TextSpan] for [node] purely from [theme] — no controller, no
/// diagnostics, no offset tracking. For read-only, static syntax-colored
/// code (e.g. an example snippet in a details panel); [TypstEditorController]
/// has its own richer version of this same recursion for the live editor,
/// which additionally lines diagnostics' wavy underlines up against it.
TextSpan typstHighlightedSpan(TypstHighlightNode node, TypstSyntaxTheme theme, {TextStyle? style}) {
  final tagStyle = node.tag != null ? theme.styleFor(node.tag!) : null;
  if (node.children.isEmpty) {
    return TextSpan(text: node.text, style: tagStyle ?? style);
  }
  return TextSpan(
    style: tagStyle ?? style,
    children: [for (final child in node.children) typstHighlightedSpan(child, theme)],
  );
}
