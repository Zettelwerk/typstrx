import '../rust/api/types.dart' as rust;

/// A syntax-highlighting category for Typst source, mirroring Typst's own
/// `Tag` enum.
enum TypstHighlightTag {
  comment,
  punctuation,
  escape,
  strong,
  emph,
  link,
  raw,
  label,
  ref,
  heading,
  listMarker,
  listTerm,
  mathDelimiter,
  mathOperator,
  mathGroupingParens,
  keyword,
  // `operator` is a reserved identifier in Dart; matches the FRB-generated
  // `HighlightTag.operator_` naming.
  operator_,
  number,
  string,
  function,
  interpolated,
  error,
}

/// One node of a syntax-highlighting tree for Typst source.
///
/// Mirrors the shape of the parse tree: a node with [children] is a
/// grouping construct (e.g. strong emphasis, a heading) and its own [text]
/// is empty; a node with no children is a leaf and [text] is its literal
/// source text. Concatenating every leaf's [text] in tree order reproduces
/// the exact source that was highlighted — [TypstEditorController] relies on
/// this to track UTF-16 offsets (for lining diagnostics up with the right
/// characters) without any offset ever crossing the bridge.
class TypstHighlightNode {
  const TypstHighlightNode({
    required this.tag,
    required this.text,
    required this.children,
  });

  /// The highlighting category, if any. Null for plain/ungrouped nodes.
  final TypstHighlightTag? tag;

  /// This node's literal text, non-empty only for leaves.
  final String text;

  /// Child nodes, non-empty only for non-leaves.
  final List<TypstHighlightNode> children;

  /// Converts a bridge-level highlight tree.
  static TypstHighlightNode fromRust(rust.HighlightNode node) {
    return TypstHighlightNode(
      tag: node.tag != null ? _tagFromRust(node.tag!) : null,
      text: node.text,
      children: [for (final child in node.children) fromRust(child)],
    );
  }

  static TypstHighlightTag _tagFromRust(rust.HighlightTag tag) {
    return switch (tag) {
      rust.HighlightTag.comment => TypstHighlightTag.comment,
      rust.HighlightTag.punctuation => TypstHighlightTag.punctuation,
      rust.HighlightTag.escape => TypstHighlightTag.escape,
      rust.HighlightTag.strong => TypstHighlightTag.strong,
      rust.HighlightTag.emph => TypstHighlightTag.emph,
      rust.HighlightTag.link => TypstHighlightTag.link,
      rust.HighlightTag.raw => TypstHighlightTag.raw,
      rust.HighlightTag.label => TypstHighlightTag.label,
      rust.HighlightTag.ref => TypstHighlightTag.ref,
      rust.HighlightTag.heading => TypstHighlightTag.heading,
      rust.HighlightTag.listMarker => TypstHighlightTag.listMarker,
      rust.HighlightTag.listTerm => TypstHighlightTag.listTerm,
      rust.HighlightTag.mathDelimiter => TypstHighlightTag.mathDelimiter,
      rust.HighlightTag.mathOperator => TypstHighlightTag.mathOperator,
      rust.HighlightTag.mathGroupingParens =>
        TypstHighlightTag.mathGroupingParens,
      rust.HighlightTag.keyword => TypstHighlightTag.keyword,
      rust.HighlightTag.operator_ => TypstHighlightTag.operator_,
      rust.HighlightTag.number => TypstHighlightTag.number,
      rust.HighlightTag.string => TypstHighlightTag.string,
      rust.HighlightTag.function => TypstHighlightTag.function,
      rust.HighlightTag.interpolated => TypstHighlightTag.interpolated,
      rust.HighlightTag.error => TypstHighlightTag.error,
    };
  }
}
