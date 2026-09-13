//! Syntax highlighting for Typst source, independent of compilation.
//!
//! Mirrors the recursion in `typst_syntax::highlight_html` (the upstream
//! reference walker), but builds a [`HighlightNode`] tree instead of an HTML
//! string: leaves carry their own text, so concatenating every leaf in tree
//! order reproduces the source exactly and callers never need to convert or
//! track byte/UTF-16 offsets separately.
//!
//! This only parses — it never touches a [`crate::world::TypstrxWorld`], so
//! it takes no lock and cannot contend with an in-flight compile or render.

use typst_syntax::{highlight, LinkedNode, Tag};

use crate::api::types::{HighlightNode, HighlightTag};

/// Parses `text` and walks it into a highlight tree.
pub fn highlight_source(text: &str) -> HighlightNode {
    let root = typst_syntax::parse(text);
    build(&LinkedNode::new(&root))
}

/// Builds one tree node, recursing into children for non-leaf nodes.
///
/// `Tag::Error` is deliberately dropped: error indication is the
/// diagnostics layer's job (see `TypstDiagnostic`), and coloring a whole
/// error-recovery node — which can span far more than the actual mistake —
/// would fight with it. This matches upstream's own `highlight_html`, which
/// skips wrapping `Error` nodes in a `<span>`.
fn build(node: &LinkedNode) -> HighlightNode {
    let tag = highlight(node)
        .filter(|tag| *tag != Tag::Error)
        .map(HighlightTag::from);

    let leaf = node.leaf_text();
    if !leaf.is_empty() {
        return HighlightNode {
            tag,
            text: leaf.to_string(),
            children: Vec::new(),
        };
    }

    HighlightNode {
        tag,
        text: String::new(),
        children: node.children().map(|child| build(&child)).collect(),
    }
}

impl From<Tag> for HighlightTag {
    fn from(tag: Tag) -> Self {
        match tag {
            Tag::Comment => HighlightTag::Comment,
            Tag::Punctuation => HighlightTag::Punctuation,
            Tag::Escape => HighlightTag::Escape,
            Tag::Strong => HighlightTag::Strong,
            Tag::Emph => HighlightTag::Emph,
            Tag::Link => HighlightTag::Link,
            Tag::Raw => HighlightTag::Raw,
            Tag::Label => HighlightTag::Label,
            Tag::Ref => HighlightTag::Ref,
            Tag::Heading => HighlightTag::Heading,
            Tag::ListMarker => HighlightTag::ListMarker,
            Tag::ListTerm => HighlightTag::ListTerm,
            Tag::MathDelimiter => HighlightTag::MathDelimiter,
            Tag::MathOperator => HighlightTag::MathOperator,
            Tag::MathGroupingParens => HighlightTag::MathGroupingParens,
            Tag::Keyword => HighlightTag::Keyword,
            Tag::Operator => HighlightTag::Operator,
            Tag::Number => HighlightTag::Number,
            Tag::String => HighlightTag::String,
            Tag::Function => HighlightTag::Function,
            Tag::Interpolated => HighlightTag::Interpolated,
            Tag::Error => HighlightTag::Error,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every leaf's text, concatenated in tree order, must reproduce the
    /// exact input. The editor controller relies on this to track UTF-16
    /// offsets client-side without the bridge ever sending a range — if it
    /// ever broke, diagnostic squiggles would silently land on the wrong
    /// characters.
    fn concat_leaves(node: &HighlightNode, out: &mut String) {
        if node.children.is_empty() {
            out.push_str(&node.text);
        } else {
            for child in &node.children {
                concat_leaves(child, out);
            }
        }
    }

    #[track_caller]
    fn assert_roundtrips(source: &str) {
        let tree = highlight_source(source);
        let mut rebuilt = String::new();
        concat_leaves(&tree, &mut rebuilt);
        assert_eq!(rebuilt, source);
    }

    #[test]
    fn leaves_reconstruct_the_source() {
        assert_roundtrips("");
        assert_roundtrips("= Hello, *world*!");
        assert_roundtrips("#let f(x) = x + 1\n#f(41)");
        assert_roundtrips("$ sum_(k=1)^n k^2 = (n(n+1)(2n+1))/6 $");
        // Non-ASCII: an em dash and CJK text must round-trip in UTF-16 terms
        // too, since that is how the editor indexes the Dart string.
        assert_roundtrips("An em dash — and 日本語 text.");
        // Deliberately malformed input exercises the Error-node path.
        assert_roundtrips("#let x = (");
    }

    #[test]
    fn error_nodes_are_not_tagged() {
        let tree = highlight_source("#let x = (");
        fn assert_no_error_tag(node: &HighlightNode) {
            assert!(!matches!(node.tag, Some(HighlightTag::Error)));
            for child in &node.children {
                assert_no_error_tag(child);
            }
        }
        assert_no_error_tag(&tree);
    }

    #[test]
    fn tags_landmarks() {
        // Smoke-check a few well-known constructs land the tag categories a
        // caller's theme would actually key off, without pinning down the
        // exact tree shape (that is upstream's `highlight`'s job, not
        // ours — this just checks the walk reaches them at all).
        fn any_tag(node: &HighlightNode, tag: HighlightTag) -> bool {
            node.tag == Some(tag) || node.children.iter().any(|child| any_tag(child, tag))
        }

        let tree = highlight_source("= Heading\n*strong* _emph_ `raw` #f()");
        assert!(any_tag(&tree, HighlightTag::Heading));
        assert!(any_tag(&tree, HighlightTag::Strong));
        assert!(any_tag(&tree, HighlightTag::Emph));
        assert!(any_tag(&tree, HighlightTag::Raw));
        assert!(any_tag(&tree, HighlightTag::Function));
    }
}
