//! Completions and hover tooltips for Typst source, via `typst-ide`.
//!
//! Unlike [`crate::highlight`], these analyze the World's own registered
//! [`Source`] (as of the last `compile()` call) rather than an independently
//! constructed one carrying the caller's very latest, possibly-uncompiled
//! edits. That is not a style choice: `typst_ide`'s value-aware analysis
//! (field-access completions, "show computed value" hover, anything that
//! isn't pure syntax) traces back through `World::source`/`World::file` to
//! re-evaluate a span, and that only resolves against the exact `Source`
//! object the World hands out — a freshly built `Source::new(id, same_text)`
//! has different internal span numbering and silently resolves nothing.
//! Verified empirically (not assumed): an identical-text detached `Source`
//! produced `None` for every tooltip in this file's test suite until
//! switched to `world.source(world.main())`.
//!
//! The cost of that choice is staleness relative to mid-edit keystrokes,
//! which the caller must guard against — see [`crate::api::types::CompletionResult`].

use typst_ide::IdeWorld;
use typst_layout::PagedDocument;
use typst_syntax::{Side, Source};

use crate::api::types::{TypstCompletion, TypstCompletionKind, TypstTooltip};

/// Computes completions at `cursor_utf16` in `source` (the World's own
/// registered source — see the module docs for why). Returns the "apply
/// from" offset (UTF-16) and the candidate list; empty when nothing applies
/// or `cursor_utf16` doesn't land on a valid position.
pub fn complete(
    world: &dyn IdeWorld,
    doc: Option<&PagedDocument>,
    source: &Source,
    cursor_utf16: u32,
    explicit: bool,
) -> (u32, Vec<TypstCompletion>) {
    let Some(cursor) = source.lines().utf16_to_byte(cursor_utf16 as usize) else {
        return (cursor_utf16, Vec::new());
    };
    let Some((from, completions)) = typst_ide::autocomplete(world, doc, source, cursor, explicit)
    else {
        return (cursor_utf16, Vec::new());
    };
    let apply_from_utf16 = source
        .lines()
        .byte_to_utf16(from)
        .map(|v| v as u32)
        .unwrap_or(cursor_utf16);
    (
        apply_from_utf16,
        completions.into_iter().map(TypstCompletion::from).collect(),
    )
}

/// Computes a hover tooltip at `cursor_utf16` in `source` (the World's own
/// registered source — see the module docs for why).
pub fn hover(
    world: &dyn IdeWorld,
    doc: Option<&PagedDocument>,
    source: &Source,
    cursor_utf16: u32,
) -> Option<TypstTooltip> {
    let cursor = source.lines().utf16_to_byte(cursor_utf16 as usize)?;
    // `Side::After`, not `Before`: hover wants the token the cursor sits
    // *at* (e.g. positioned right after `#`, before `box`, should describe
    // `box`), unlike `autocomplete`'s own internal leaf lookup, which wants
    // what was just typed *before* the cursor. Verified against upstream's
    // own tooltip test fixtures, which consistently probe with `After`.
    typst_ide::tooltip(world, doc, source, cursor, Side::After).map(TypstTooltip::from)
}

impl From<typst_ide::Completion> for TypstCompletion {
    fn from(c: typst_ide::Completion) -> Self {
        TypstCompletion {
            kind: c.kind.into(),
            apply: c
                .apply
                .map(|s| s.to_string())
                .unwrap_or_else(|| c.label.to_string()),
            label: c.label.to_string(),
            detail: c.detail.map(|s| s.to_string()),
        }
    }
}

impl From<typst_ide::CompletionKind> for TypstCompletionKind {
    fn from(kind: typst_ide::CompletionKind) -> Self {
        use typst_ide::CompletionKind as K;
        match kind {
            K::Syntax => TypstCompletionKind::Syntax,
            K::Func => TypstCompletionKind::Func,
            K::Type => TypstCompletionKind::Type,
            K::Param => TypstCompletionKind::Param,
            K::Constant => TypstCompletionKind::Constant,
            K::Path => TypstCompletionKind::Path,
            K::Package => TypstCompletionKind::Package,
            K::Label => TypstCompletionKind::Label,
            K::Font => TypstCompletionKind::Font,
            K::Symbol(notation) => TypstCompletionKind::Symbol {
                notation: notation.to_string(),
            },
        }
    }
}

impl From<typst_ide::Tooltip> for TypstTooltip {
    fn from(tooltip: typst_ide::Tooltip) -> Self {
        match tooltip {
            typst_ide::Tooltip::Text(s) => TypstTooltip::Text {
                content: s.to_string(),
            },
            typst_ide::Tooltip::Code(s) => TypstTooltip::Code {
                content: s.to_string(),
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use typst::World;
    use typst_layout::PagedDocument;

    use super::*;
    use crate::world::{TypstrxWorld, WorldOptions};

    fn world_with_source(text: &str) -> TypstrxWorld {
        let mut world = TypstrxWorld::new(WorldOptions {
            package_cache_dir: None,
            allow_package_download: false,
        });
        world.set_main_source(text);
        world
    }

    #[test]
    fn completes_a_keyword_prefix() {
        // typst-ide does not itself filter by what's already been typed —
        // it returns every candidate valid at this syntactic position, and
        // leaves prefix/fuzzy filtering to the caller (this is why the
        // completion is labeled "let binding", not the bare keyword "let":
        // labels are meant for a filterable, human-readable list).
        let world = world_with_source("#le");
        let source = world.source(world.main()).unwrap();
        let (_, completions) = complete(&world, None::<&PagedDocument>, &source, 3, false);
        assert!(
            completions.iter().any(|c| c.label == "let binding"),
            "expected a `let binding` completion, got {:?}",
            completions.iter().map(|c| &c.label).collect::<Vec<_>>()
        );
    }

    #[test]
    fn apply_from_and_cursor_round_trip_non_ascii() {
        // "日本語#le" — the prefix is 4 non-ASCII UTF-16 code units (each
        // character here is one UTF-16 unit) before the '#'.
        let text = "日本語#le";
        let world = world_with_source(text);
        let source = world.source(world.main()).unwrap();
        let cursor_utf16 = text.encode_utf16().count() as u32;
        let (apply_from_utf16, completions) =
            complete(&world, None::<&PagedDocument>, &source, cursor_utf16, false);
        assert!(completions.iter().any(|c| c.label == "let binding"));
        // "apply from" must land right after '#', i.e. 4 UTF-16 units in.
        assert_eq!(apply_from_utf16, 4);
    }

    #[test]
    fn out_of_range_cursor_returns_empty_not_panic() {
        let world = world_with_source("#let");
        let source = world.source(world.main()).unwrap();
        let (_, completions) = complete(&world, None::<&PagedDocument>, &source, 999, false);
        assert!(completions.is_empty());
    }

    #[test]
    fn completes_field_access() {
        // Exercises the value-aware completion path (as opposed to pure
        // keyword/global completion) — this is the path that specifically
        // needs the World's own `Source` to resolve at all.
        let world = world_with_source("#emoji.");
        let source = world.source(world.main()).unwrap();
        let (_, completions) = complete(&world, None::<&PagedDocument>, &source, 7, false);
        assert!(!completions.is_empty(), "expected emoji field completions");
    }

    #[test]
    fn hover_returns_none_on_plain_text() {
        let world = world_with_source("hello world");
        let source = world.source(world.main()).unwrap();
        // Plain markup text carries no hoverable expression.
        assert!(hover(&world, None::<&PagedDocument>, &source, 2).is_none());
    }

    #[test]
    fn hover_describes_a_computed_expression() {
        let world = world_with_source("#(1+2)");
        let source = world.source(world.main()).unwrap();
        // Cursor right after '#', at the start of the parenthesized expr.
        let tooltip = hover(&world, None::<&PagedDocument>, &source, 1);
        match tooltip {
            Some(TypstTooltip::Code { content }) => assert_eq!(content, "3"),
            other => panic!("expected a Code tooltip showing the computed value, got {other:?}"),
        }
    }
}
