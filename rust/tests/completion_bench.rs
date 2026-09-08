//! Not a correctness test — measures completion/hover latency to inform
//! TypstEditorController's trigger policy (every keystroke vs. debounced vs.
//! explicit-only). Run with `cargo test --release --test completion_bench --
//! --nocapture --ignored`.
//!
//! Unlike `highlight`, completions/hover are always triggered by a discrete
//! UI event (a trigger character, a pause, an explicit request), never on
//! `buildTextSpan`'s synchronous critical path — so this isn't deciding
//! `#[frb(sync)]` vs. async the way highlight_bench was. It's just sizing
//! the trigger policy against real latency.

use std::time::Instant;

use typstrx::api::session::TypstSession;
use typstrx::api::types::SessionOptions;

fn session() -> TypstSession {
    TypstSession::create(SessionOptions {
        package_cache_dir: None,
        allow_package_download: false,
    })
}

const DENSE_MULTI_PAGE: &str = "#for i in range(5) [\n= Page #i\n#lorem(200)\n#pagebreak()\n]";

fn bench_one(name: &str, source: &str, cursor_utf16: u32, explicit: bool) {
    let s = session();
    // Deliberately not asserting success: completions are routinely
    // requested mid-keyword or mid-expression, exactly when the document
    // does *not* currently compile. `compile()` still registers the source
    // with the World regardless of outcome, which is all completions/hover
    // need (see CompletionResult's doc comment).
    s.compile(source.to_owned());

    let start = Instant::now();
    let result = s.completions(cursor_utf16, explicit);
    let elapsed = start.elapsed();
    println!(
        "  completions  {name:<28} n={:>4}  {:>7.3} ms",
        result.completions.len(),
        elapsed.as_secs_f64() * 1000.0,
    );

    let start = Instant::now();
    let hover = s.hover(cursor_utf16);
    let elapsed = start.elapsed();
    println!(
        "  hover        {name:<28} some={:<5} {:>7.3} ms",
        hover.tooltip.is_some(),
        elapsed.as_secs_f64() * 1000.0,
    );
}

#[test]
#[ignore]
fn bench_completion_positions() {
    println!("\n== completions + hover latency ==");
    // Global/keyword completion right after '#' in a small doc.
    bench_one("small doc, keyword", "#le", 3, false);
    // Field-access completion (value-aware — the expensive path).
    bench_one("small doc, field access", "#emoji.", 7, false);
    // Same, but in a larger, denser document (more to search/trace through).
    let cursor = DENSE_MULTI_PAGE.len() as u32; // end of source
    bench_one("dense multi-page doc, end", DENSE_MULTI_PAGE, cursor, false);
    let source_with_prefix = format!("{DENSE_MULTI_PAGE}\n#emoji.");
    let cursor = source_with_prefix.len() as u32;
    bench_one(
        "dense multi-page doc, field access",
        &source_with_prefix,
        cursor,
        false,
    );
}

#[test]
#[ignore]
fn bench_repeated_completion_calls() {
    // Simulates a completion popup re-querying on every keystroke while the
    // user narrows a field-access completion (the expensive path).
    let s = session();
    let source = "#emoji.a";
    let compiled = s.compile(source.to_owned());
    assert!(compiled.success);
    let iterations = 20;
    println!("\n== {iterations} sequential completion calls (field access) ==");
    let start = Instant::now();
    for _ in 0..iterations {
        std::hint::black_box(s.completions(8, false));
    }
    let elapsed = start.elapsed();
    println!(
        "  total={:.2} ms  avg={:.3} ms/call",
        elapsed.as_secs_f64() * 1000.0,
        elapsed.as_secs_f64() * 1000.0 / iterations as f64,
    );
}
