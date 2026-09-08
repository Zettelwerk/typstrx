//! Folding ranges for Typst source, independent of compilation.
//!
//! Parse-only, like [`crate::highlight`]: never touches a [`crate::world::TypstrxWorld`],
//! so it takes no lock and cannot contend with an in-flight compile or
//! render.
//!
//! Headings are deliberately left out. Every other construct here is
//! delimited (`{`/`}`, `[`/`]`, `(`/`)`, `/*`/`*/`), so its fold range is
//! just that node's own span. A heading has no closing delimiter — its fold
//! region would end wherever the next heading of equal-or-higher level
//! starts, which needs sibling-scanning with level comparison rather than a
//! single node lookup. That is also the one part of this feature most
//! likely to produce a subtly wrong range, and there is no visual fold UI
//! yet to catch a wrong one by eye (`TypstCodeEditor` does not render
//! folded regions at all — this only computes where they'd be).

use typst_syntax::{LinkedNode, Source, SyntaxKind};

use crate::api::types::{TypstFoldingKind, TypstFoldingRange};

/// Parses `text` and collects folding ranges for every block-shaped
/// construct that spans more than one line. A construct confined to a
/// single line is skipped — collapsing it would hide nothing.
pub fn folding_ranges(text: &str) -> Vec<TypstFoldingRange> {
    let source = Source::detached(text);
    let mut ranges = Vec::new();
    collect(&LinkedNode::new(source.root()), &source, &mut ranges);
    ranges
}

fn collect(node: &LinkedNode, source: &Source, out: &mut Vec<TypstFoldingRange>) {
    if let Some(kind) = fold_kind(node.kind()) {
        if let Some(range) = fold_range(node, source) {
            out.push(TypstFoldingRange {
                start_utf16: range.0,
                end_utf16: range.1,
                kind,
            });
        }
    }
    for child in node.children() {
        collect(&child, source, out);
    }
}

fn fold_kind(kind: SyntaxKind) -> Option<TypstFoldingKind> {
    match kind {
        SyntaxKind::CodeBlock => Some(TypstFoldingKind::CodeBlock),
        SyntaxKind::ContentBlock => Some(TypstFoldingKind::ContentBlock),
        SyntaxKind::Args => Some(TypstFoldingKind::Args),
        SyntaxKind::Array => Some(TypstFoldingKind::Array),
        SyntaxKind::Dict => Some(TypstFoldingKind::Dict),
        SyntaxKind::BlockComment => Some(TypstFoldingKind::Comment),
        _ => None,
    }
}

/// The node's byte range converted to UTF-16 offsets, or `None` if it
/// doesn't span multiple lines (or a conversion fails, which in practice
/// only happens for a range past the end of a text `Source::detached`
/// itself just produced — defensive, not expected to trigger).
fn fold_range(node: &LinkedNode, source: &Source) -> Option<(u32, u32)> {
    let range = node.range();
    let lines = source.lines();
    let start_line = lines.byte_to_line(range.start)?;
    let end_line = lines.byte_to_line(range.end)?;
    if start_line == end_line {
        return None;
    }
    let start_utf16 = lines.byte_to_utf16(range.start)? as u32;
    let end_utf16 = lines.byte_to_utf16(range.end)? as u32;
    Some((start_utf16, end_utf16))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folds_a_multiline_code_block() {
        let ranges = folding_ranges("#{\n  let x = 1\n  x + 1\n}");
        assert_eq!(ranges.len(), 1);
        assert_eq!(ranges[0].kind, TypstFoldingKind::CodeBlock);
        assert_eq!(ranges[0].start_utf16, 1); // the '{'
        assert_eq!(ranges[0].end_utf16, 24); // the '}'
    }

    #[test]
    fn skips_a_single_line_code_block() {
        let ranges = folding_ranges("#{ let x = 1; x + 1 }");
        assert!(ranges.is_empty());
    }

    #[test]
    fn folds_nested_constructs_independently() {
        // A multiline content block (a bracket call argument, since a bare
        // top-level `[...]` in markup is just literal text, not a
        // ContentBlock node) containing a multiline code block: both
        // should fold, innermost included.
        let text = "#box[\n  #{\n    1\n  }\n]";
        let ranges = folding_ranges(text);
        assert!(ranges.iter().any(|r| r.kind == TypstFoldingKind::ContentBlock));
        assert!(ranges.iter().any(|r| r.kind == TypstFoldingKind::CodeBlock));
        let content = ranges
            .iter()
            .find(|r| r.kind == TypstFoldingKind::ContentBlock)
            .unwrap();
        let code = ranges
            .iter()
            .find(|r| r.kind == TypstFoldingKind::CodeBlock)
            .unwrap();
        assert!(content.start_utf16 < code.start_utf16);
        assert!(content.end_utf16 > code.end_utf16);
    }

    #[test]
    fn folds_a_multiline_array_and_dict() {
        let array = folding_ranges("#(\n  1,\n  2,\n)");
        assert_eq!(array.len(), 1);
        assert_eq!(array[0].kind, TypstFoldingKind::Array);

        let dict = folding_ranges("#(\n  a: 1,\n  b: 2,\n)");
        assert_eq!(dict.len(), 1);
        assert_eq!(dict[0].kind, TypstFoldingKind::Dict);
    }

    #[test]
    fn folds_a_multiline_function_call_args() {
        let ranges = folding_ranges("#f(\n  1,\n  2,\n)");
        assert!(
            ranges.iter().any(|r| r.kind == TypstFoldingKind::Args),
            "expected an Args range, got {ranges:?}"
        );
    }

    #[test]
    fn folds_a_multiline_block_comment() {
        let ranges = folding_ranges("/* line one\n   line two */");
        assert_eq!(ranges.len(), 1);
        assert_eq!(ranges[0].kind, TypstFoldingKind::Comment);
    }

    #[test]
    fn line_comments_never_fold() {
        // A line comment cannot itself span multiple lines by definition;
        // this just confirms one doesn't somehow produce a range.
        let ranges = folding_ranges("// a line comment\n// another one");
        assert!(ranges.is_empty());
    }

    #[test]
    fn an_unclosed_block_does_not_panic_or_emit_a_backwards_range() {
        // The parser recovers with an error node rather than panicking;
        // whatever range (if any) comes out must still satisfy start <= end.
        let ranges = folding_ranges("#{\n  let x = 1\n");
        for r in &ranges {
            assert!(
                r.start_utf16 <= r.end_utf16,
                "backwards range: {} > {}",
                r.start_utf16,
                r.end_utf16
            );
        }
    }

    #[test]
    fn empty_source_has_no_folds() {
        assert!(folding_ranges("").is_empty());
    }
}
