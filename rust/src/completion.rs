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

use typst::foundations::{Func, Value};
use typst_ide::IdeWorld;
use typst_layout::PagedDocument;
use typst_syntax::ast::AstNode;
use typst_syntax::{LinkedNode, Side, Source, ast};

use crate::api::types::{
    TypstCompletion, TypstCompletionKind, TypstFunctionInfo, TypstSignatureToken,
    TypstSignatureTokenKind, TypstTooltip,
};

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

/// Looks up documentation for the function named `label`. See
/// [`crate::api::session::TypstSession::function_info`] for the resolution
/// order (cursor context, then a global-scope lookup by `label`) and its
/// scope limitations.
pub fn function_info(
    world: &dyn IdeWorld,
    source: &Source,
    cursor_utf16: u32,
    label: &str,
) -> Option<TypstFunctionInfo> {
    let func = source
        .lines()
        .utf16_to_byte(cursor_utf16 as usize)
        .and_then(|cursor| resolve_func_at_cursor(world, source, cursor))
        .or_else(|| resolve_global_func(world, label))?;
    Some(describe_func(&func))
}

/// Resolves the `Func` that governs `cursor`'s position — the callee of the
/// nearest enclosing call or set rule, if any. Mirrors (a simplified,
/// public-API-only version of) how `typst_ide::complete::param_completions`
/// itself resolves the function whose parameters it's completing.
fn resolve_func_at_cursor(world: &dyn IdeWorld, source: &Source, cursor: usize) -> Option<Func> {
    let root = LinkedNode::new(source.root());
    let mut node = root.leaf_at(cursor, Side::Before)?;
    loop {
        if let Some(expr) = node.cast::<ast::Expr>() {
            let callee = match expr {
                ast::Expr::FuncCall(call) => Some(call.callee()),
                ast::Expr::SetRule(set) => Some(set.target()),
                _ => None,
            };
            let func = callee
                .and_then(|c| node.find(c.span()))
                .and_then(|callee_node| resolve_expr(world, &callee_node))
                .and_then(as_func);
            if let Some(func) = func {
                return Some(func);
            }
        }
        node = node.parent()?.clone();
    }
}

fn as_func(value: Value) -> Option<Func> {
    match value {
        Value::Func(func) => Some(func),
        _ => None,
    }
}

/// Resolves a plain identifier or one level of field access to a value,
/// against the global scope — a deliberately narrow, public-API-only stand-in
/// for `typst_ide::analyze::analyze_expr_with_fallback` (not exported by
/// `typst_ide`). Doesn't trace actual execution, so it won't resolve local
/// variables or closures — only built-ins reachable from the global scope.
fn resolve_expr(world: &dyn IdeWorld, node: &LinkedNode) -> Option<Value> {
    match node.cast::<ast::Expr>()? {
        ast::Expr::Ident(ident) => {
            Some(world.library().global.scope().get(&ident)?.read().clone())
        }
        ast::Expr::FieldAccess(access) => {
            let target = match access.target() {
                ast::Expr::Ident(target) => target,
                _ => return None,
            };
            let target_value = world.library().global.scope().get(&target)?.read();
            Some(target_value.scope()?.get(&access.field())?.read().clone())
        }
        _ => None,
    }
}

/// A last-resort lookup for when there's no resolvable expression at the
/// cursor yet (e.g. browsing completions for a partially typed identifier
/// like `#re|`) — just the bare name in the global scope. Won't find
/// anything behind field access (`calc.abs`) or user-defined functions.
fn resolve_global_func(world: &dyn IdeWorld, label: &str) -> Option<Func> {
    let value = world.library().global.scope().get(label)?.read();
    match value {
        Value::Func(func) => Some(func.clone()),
        _ => None,
    }
}

fn describe_func(func: &Func) -> TypstFunctionInfo {
    let name = func.name().unwrap_or("").to_string();
    let signature = signature_tokens(&name, func);
    let docs = func.docs();
    let example = docs.and_then(extract_example);
    let example_highlight = example.as_deref().map(crate::highlight::highlight_source);
    let description = docs
        .map(|d| d.split("= Example").next().unwrap_or(d).trim().to_string())
        .filter(|d| !d.is_empty());
    TypstFunctionInfo { name, signature, description, example, example_highlight }
}

/// Builds a signature like `rect(width?:, height?:, fill?:, body)`, split
/// into name/param/punctuation pieces so a caller can color them
/// differently — see [`TypstSignatureToken`].
fn signature_tokens(name: &str, func: &Func) -> Vec<TypstSignatureToken> {
    fn text(text: impl Into<String>, kind: TypstSignatureTokenKind) -> TypstSignatureToken {
        TypstSignatureToken { text: text.into(), kind }
    }
    use TypstSignatureTokenKind::{Name, Param, Punctuation};

    let mut tokens = vec![text(name, Name), text("(", Punctuation)];
    let mut first = true;
    for param in func.params() {
        let Some(param_name) = param.name() else { continue };
        if !first {
            tokens.push(text(", ", Punctuation));
        }
        first = false;
        tokens.push(text(param_name, Param));
        if param.variadic() {
            tokens.push(text(": ..", Punctuation));
        } else if param.named() {
            if !param.required() {
                tokens.push(text("?", Punctuation));
            }
            tokens.push(text(":", Punctuation));
        }
    }
    tokens.push(text(")", Punctuation));
    tokens
}

/// Extracts the code inside a docstring's first ` ```example ` fenced block,
/// if it has one. Native function doc comments in `typst-library` (e.g.
/// `rect`'s) embed a runnable example this way, under an `= Example`
/// heading — the heading itself is left in `description`'s cut point, not
/// duplicated here.
fn extract_example(docs: &str) -> Option<String> {
    let start = docs.find("```example")?;
    let after = &docs[start + "```example".len()..];
    let after = after.strip_prefix('\n').unwrap_or(after);
    let end = after.find("```")?;
    Some(after[..end].trim_end().to_string())
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

    #[test]
    fn function_info_resolves_by_label_while_browsing_completions() {
        // Cursor at the end of "#re" — there's no call yet, so this exercises
        // the global-scope-by-label fallback, not the cursor-context path.
        let world = world_with_source("#re");
        let source = world.source(world.main()).unwrap();
        let info = function_info(&world, &source, 3, "rect").expect("expected rect to resolve");
        assert_eq!(info.name, "rect");
        let signature_text: String = info.signature.iter().map(|t| t.text.as_str()).collect();
        assert!(signature_text.starts_with("rect("), "{signature_text}");
        assert!(signature_text.contains("width"), "{signature_text}");
        assert!(
            info.signature.iter().any(|t| t.text == "width" && matches!(t.kind, TypstSignatureTokenKind::Param)),
            "expected a Param-kind token for width, got {signature_text}"
        );
        let description = info.description.expect("expected a description");
        assert!(
            !description.contains("```example"),
            "example fence should not leak into description: {description}"
        );
        let example = info.example.expect("expected an extracted example");
        assert!(example.contains("rect("), "{example}");
        let example_highlight = info.example_highlight.expect("expected an example highlight tree");
        assert!(!example_highlight.children.is_empty(), "expected the example to actually be parsed");
    }

    #[test]
    fn function_info_resolves_via_cursor_context_inside_a_call() {
        // Cursor inside "#rect(|" — exercises the callee-at-cursor path
        // directly, independent of `label`.
        let world = world_with_source("#rect()");
        let source = world.source(world.main()).unwrap();
        // Bogus label: proves this resolved via cursor context, not the
        // fallback.
        let info = function_info(&world, &source, 6, "not-rect").expect("expected rect to resolve");
        assert_eq!(info.name, "rect");
    }

    #[test]
    fn function_info_is_none_for_an_unresolvable_label() {
        let world = world_with_source("#zz");
        let source = world.source(world.main()).unwrap();
        assert!(function_info(&world, &source, 3, "not-a-real-function").is_none());
    }
}
