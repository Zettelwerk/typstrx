//! Not a correctness test — prints render-time/memory data across scales to
//! inform TypstViewerParams' default maxRenderScale/previewScaleCap. Run
//! with `cargo test --test render_bench -- --nocapture --ignored`.

use std::time::Instant;

use typstrx::api::session::TypstSession;
use typstrx::api::types::SessionOptions;

fn session() -> TypstSession {
    TypstSession::create(SessionOptions {
        package_cache_dir: None,
        allow_package_download: false,
    })
}

const TEXT_HEAVY: &str = "= A Typical Document\n#lorem(400)";
const MATH_HEAVY: &str = "= Formulas\n#for i in range(30) [\n$ sum_(k=1)^n k^#i = integral_0^n x^#i dif x + O(n^#i) $\n]";
const DENSE_MULTI_PAGE: &str = "#for i in range(5) [\n= Page #i\n#lorem(200)\n#pagebreak()\n]";

fn bench_full_page(name: &str, source: &str, scales: &[f64]) {
    let s = session();
    let result = s.compile(source.to_owned());
    assert!(
        result.success,
        "{name} failed to compile: {:?}",
        result
            .diagnostics
            .iter()
            .map(|d| &d.message)
            .collect::<Vec<_>>()
    );
    let page = &result.pages[0];
    println!(
        "\n== {name} (page: {:.0}x{:.0}pt) ==",
        page.width_pt, page.height_pt
    );
    for &scale in scales {
        let full_w = (page.width_pt * scale).round() as u32;
        let full_h = (page.height_pt * scale).round() as u32;
        let start = Instant::now();
        let region = s
            .render_page_region(
                result.generation,
                0,
                0,
                0,
                full_w,
                full_h,
                full_w,
                full_h,
                0xffffffff,
            )
            .unwrap();
        let elapsed = start.elapsed();
        let mb = (region.pixels.len() as f64) / (1024.0 * 1024.0);
        println!(
            "  scale={scale:>4.1}x ({:>4}dpi)  {full_w:>5}x{full_h:<5}px  {:>7.2} MB  {:>6.1} ms",
            (scale * 72.0) as u32,
            mb,
            elapsed.as_secs_f64() * 1000.0,
        );
    }
}

/// Simulates a hi-res tile: only the viewport-sized visible window of a
/// full page rendered at `scale`, not the whole page.
fn bench_tile(name: &str, source: &str, viewport_px: (u32, u32), scales: &[f64]) {
    let s = session();
    let result = s.compile(source.to_owned());
    assert!(result.success);
    let page = &result.pages[0];
    println!(
        "\n== {name} tile (viewport {}x{}px) ==",
        viewport_px.0, viewport_px.1
    );
    for &scale in scales {
        let full_w = (page.width_pt * scale).round() as u32;
        let full_h = (page.height_pt * scale).round() as u32;
        let (tw, th) = (viewport_px.0.min(full_w), viewport_px.1.min(full_h));
        let start = Instant::now();
        let region = s
            .render_page_region(
                result.generation,
                0,
                0,
                0,
                tw,
                th,
                full_w,
                full_h,
                0xffffffff,
            )
            .unwrap();
        let elapsed = start.elapsed();
        let mb = (region.pixels.len() as f64) / (1024.0 * 1024.0);
        println!(
            "  scale={scale:>4.1}x ({:>4}dpi)  full={full_w:>5}x{full_h:<5}px  tile={tw}x{th}  {:>6.2} MB  {:>6.1} ms",
            (scale * 72.0) as u32,
            mb,
            elapsed.as_secs_f64() * 1000.0,
        );
    }
}

#[test]
#[ignore]
fn bench_full_page_scales() {
    let scales = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0];
    bench_full_page("text-heavy", TEXT_HEAVY, &scales);
    bench_full_page("math-heavy", MATH_HEAVY, &scales);
}

#[test]
#[ignore]
fn bench_tile_scales() {
    let scales = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0];
    // A realistic desktop viewport window over a page at various zooms.
    bench_tile("text-heavy", TEXT_HEAVY, (900, 700), &scales);
    bench_tile("math-heavy", MATH_HEAVY, (900, 700), &scales);
}

#[test]
#[ignore]
fn bench_multi_page_incremental_compile() {
    let s = session();
    let cold = s.compile(DENSE_MULTI_PAGE.to_owned());
    assert!(cold.success);
    let warm = s.compile(format!("{DENSE_MULTI_PAGE}\n// edit"));
    assert!(warm.success);
    println!(
        "\n== incremental compile: cold={} ms warm={} ms ({} pages) ==",
        cold.elapsed_ms,
        warm.elapsed_ms,
        cold.pages.len()
    );
}
