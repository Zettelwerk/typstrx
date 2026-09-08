//! Not a correctness test — measures parse+walk time across document sizes
//! to decide whether `TypstSession::highlight` can be exposed as
//! `#[frb(sync)]` (safe only if it is fast enough to call synchronously from
//! `TextEditingController.buildTextSpan`, which must return without
//! awaiting). Run with `cargo test --release --test highlight_bench --
//! --nocapture --ignored`.

use std::time::Instant;

use typstrx::api::session::TypstSession;
use typstrx::api::types::{HighlightNode, SessionOptions};

fn session() -> TypstSession {
    TypstSession::create(SessionOptions {
        package_cache_dir: None,
        allow_package_download: false,
    })
}

/// One paragraph mixing headings, emphasis, math, lists, code and comments —
/// deliberately node-dense rather than just byte-dense, since tree-walk cost
/// tracks node count more than raw text length.
fn paragraph(i: usize) -> String {
    format!(
        "= Section {i}\n\n\
         This is *strong* and _emphasized_ text with a #link(\"https://typst.app\")[hyperlink] \
         and a formula $ sum_(k=1)^n k^2 = (n(n+1)(2n+1))/6 $ inline.\n\n\
         - A list item\n- Another #emph[item] with `raw code`\n\n\
         #let f(x) = x * 2\n#f({i})\n\n\
         // a comment explaining the next block\n\
         #for j in range(3) [ Item #j ]\n\n"
    )
}

fn synthetic_doc(paragraphs: usize) -> String {
    (0..paragraphs).map(paragraph).collect()
}

fn count_leaves(node: &HighlightNode) -> usize {
    if node.children.is_empty() {
        1
    } else {
        node.children.iter().map(count_leaves).sum()
    }
}

#[test]
#[ignore]
fn bench_highlight_scales() {
    let s = session();
    // Typical editing document, a long paper, and a worst-case paste.
    let paragraph_counts = [5, 50, 500, 2_500];
    println!("\n== TypstSession::highlight (parse + tag walk) ==");
    for &n in &paragraph_counts {
        let source = synthetic_doc(n);
        let start = Instant::now();
        let tree = s.highlight(source.clone());
        let elapsed = start.elapsed();
        println!(
            "  paragraphs={n:>5}  source={:>9} bytes  leaves={:>7}  {:>7.3} ms",
            source.len(),
            count_leaves(&tree),
            elapsed.as_secs_f64() * 1000.0,
        );
    }
}

#[test]
#[ignore]
fn bench_highlight_repeated_keystrokes() {
    // Simulates typing at the end of an already-large document: every
    // keystroke re-parses the whole buffer from scratch (Phase 1 has no
    // incremental reparse), so this is the actual per-keystroke cost a user
    // would feel while editing a long document.
    let s = session();
    let base = synthetic_doc(500);
    let iterations = 50;
    println!("\n== {iterations} sequential re-highlights of a {}-byte doc ==", base.len());
    let start = Instant::now();
    for i in 0..iterations {
        let source = format!("{base}x{i}");
        std::hint::black_box(s.highlight(source));
    }
    let elapsed = start.elapsed();
    println!(
        "  total={:.2} ms  avg={:.3} ms/keystroke",
        elapsed.as_secs_f64() * 1000.0,
        elapsed.as_secs_f64() * 1000.0 / iterations as f64,
    );
}
