//! Not a correctness test — decomposes a `render_region` call into its phases
//! to size the payoff of clipped (pdfium-style) rasterization.
//!
//! `render_region` rasterizes the whole page at the requested scale and crops
//! the requested window out of it (see `src/render.rs`). pdfium instead renders
//! straight into a tile-sized bitmap (`FPDFBitmap_CreateEx(tile_w, tile_h)` +
//! `FPDF_RenderPageBitmap(bmp, page, -x, -y, full_w, full_h)`), so its cost is
//! O(visible pixels) and independent of zoom.
//!
//! Phases are separated by differential measurement, using only the public API:
//!   * A 1x1 tile pays the full-page rasterization and an ~free crop, so it
//!     measures `typst_render::render` on its own.
//!   * Subtracting that from a viewport tile / a full-page render gives each
//!     one's crop cost.
//!
//! Rasterization itself has two regimes, because `typst-render` memoizes glyph
//! rasterization on `(font, glyph, ts.tx, ts.ty, ppem)` — absolute device
//! position and size:
//!   * COLD: first render at a given scale, every glyph key new — a ZOOM.
//!   * WARM: repeat at the same scale, every glyph cached — a PAN.
//!
//! Run with `cargo test --test tile_waste_bench -- --nocapture --ignored`.

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

/// A typical desktop viewport in device pixels.
const VIEWPORT_W: u32 = 1200;
const VIEWPORT_H: u32 = 800;

fn best_ms(mut f: impl FnMut(), runs: usize) -> f64 {
    let mut best = f64::MAX;
    for _ in 0..runs {
        let start = Instant::now();
        f();
        best = best.min(start.elapsed().as_secs_f64() * 1000.0);
    }
    best
}

#[test]
#[ignore]
fn where_tile_render_time_goes() {
    let s = session();
    let result = s.compile(TEXT_HEAVY.to_owned());
    assert!(result.success, "failed to compile");
    let page = &result.pages[0];
    println!(
        "\npage {:.0}x{:.0}pt, viewport tile {VIEWPORT_W}x{VIEWPORT_H}px\n",
        page.width_pt, page.height_pt
    );
    println!(
        "raster COLD/WARM = full-page typst_render::render (1x1 tile isolates it)\n\
         crop tile/full   = pixmap alloc + fill + blit on top of that raster\n\
         tile total       = what the viewer actually pays per tile today\n"
    );
    println!(
        "{:>5}  {:>11}  {:>8}  {:>8}  {:>9}  {:>9}  {:>10}  {:>8}",
        "dpi",
        "full px",
        "rasterCOLD",
        "rasterWARM",
        "cropTile",
        "cropFull",
        "tileTotal",
        "visible%"
    );

    for dpi in [144.0_f64, 216.0, 288.0, 360.0, 500.0, 720.0] {
        let scale = dpi / 72.0;
        let full_w = (page.width_pt * scale).round() as u32;
        let full_h = (page.height_pt * scale).round() as u32;

        let tile_w = VIEWPORT_W.min(full_w);
        let tile_h = VIEWPORT_H.min(full_h);
        let x = (full_w - tile_w) / 2;
        let y = (full_h - tile_h) / 2;

        let render = |x: u32, y: u32, w: u32, h: u32| {
            s.render_page_region(result.generation, 0, x, y, w, h, full_w, full_h, 0xffffffff)
                .unwrap()
        };

        // COLD rasterization: this scale has not been rendered yet, so every
        // glyph memo key is new. The 1x1 crop is free, so this is the raster.
        let raster_cold = best_ms(
            || {
                render(0, 0, 1, 1);
            },
            1,
        );
        // WARM rasterization: same scale again, every glyph key now cached.
        let raster_warm = best_ms(
            || {
                render(0, 0, 1, 1);
            },
            5,
        );

        let tile_total = best_ms(
            || {
                render(x, y, tile_w, tile_h);
            },
            5,
        );
        let full_total = best_ms(
            || {
                render(0, 0, full_w, full_h);
            },
            3,
        );

        let full_px = u64::from(full_w) * u64::from(full_h);
        let tile_px = u64::from(tile_w) * u64::from(tile_h);
        println!(
            "{dpi:>5.0}  {:>11}  {raster_cold:>9.1}  {raster_warm:>9.1}  {:>8.1}  {:>8.1}  {tile_total:>9.1}  {:>7.1}%",
            format!("{:.1}M", (full_px as f64) / 1e6),
            tile_total - raster_warm,
            full_total - raster_warm,
            (tile_px as f64) / (full_px as f64) * 100.0,
        );
    }

    println!(
        "\nA clipped render would allocate/rasterize only the tile. Floor for the\n\
         tile-sized work alone (alloc + white fill of {VIEWPORT_W}x{VIEWPORT_H}), for scale:"
    );
    let t = best_ms(
        || {
            let mut pixmap = tiny_skia::Pixmap::new(VIEWPORT_W, VIEWPORT_H).unwrap();
            pixmap.fill(tiny_skia::Color::WHITE);
            std::hint::black_box(&pixmap);
        },
        20,
    );
    println!(
        "  {VIEWPORT_W}x{VIEWPORT_H} = {:.1} MB, {t:.2} ms",
        (u64::from(VIEWPORT_W) * u64::from(VIEWPORT_H) * 4) as f64 / (1024.0 * 1024.0)
    );

    println!("\nfull-page pixmap alloc + white fill alone (pure overhead clipping removes):");
    for dpi in [288.0_f64, 500.0, 720.0] {
        let scale = dpi / 72.0;
        let full_w = (page.width_pt * scale).round() as u32;
        let full_h = (page.height_pt * scale).round() as u32;
        let t = best_ms(
            || {
                let mut pixmap = tiny_skia::Pixmap::new(full_w, full_h).unwrap();
                pixmap.fill(tiny_skia::Color::WHITE);
                std::hint::black_box(&pixmap);
            },
            5,
        );
        println!(
            "  {dpi:>5.0} dpi  {full_w}x{full_h}  {:>6.1} MB  {t:>6.1} ms",
            (u64::from(full_w) * u64::from(full_h) * 4) as f64 / (1024.0 * 1024.0),
        );
    }
}

/// Validates the mechanism the clipped-render recommendation rests on: that
/// tiny-skia (the rasterizer under `typst-render`) actually *skips* work
/// outside the pixmap, rather than rasterizing everything and discarding.
///
/// Draws the same page-covering content twice at the same scale: once into a
/// full-page pixmap, once into a tile-sized pixmap with the transform
/// translated so the same content lands in the same place — which is exactly
/// what a clipped `typst_render::render` would do.
#[test]
#[ignore]
fn tiny_skia_clipping_actually_saves_work() {
    use tiny_skia::{Color, FillRule, Paint, PathBuilder, Pixmap, Transform};

    // Stand-in for page content: many small filled paths spread over the page,
    // like glyphs and rules on a text page.
    fn draw(pixmap: &mut Pixmap, ts: Transform, full_w: u32, full_h: u32) {
        let mut paint = Paint {
            anti_alias: true,
            ..Default::default()
        };
        let cols = 60;
        let rows = 90;
        for row in 0..rows {
            for col in 0..cols {
                let x = (col as f32 / cols as f32) * full_w as f32;
                let y = (row as f32 / rows as f32) * full_h as f32;
                let w = full_w as f32 / cols as f32 * 0.8;
                let h = full_h as f32 / rows as f32 * 0.6;
                let mut pb = PathBuilder::new();
                pb.move_to(x, y);
                pb.line_to(x + w, y + h * 0.3);
                pb.line_to(x + w * 0.7, y + h);
                pb.close();
                if let Some(path) = pb.finish() {
                    paint.set_color(Color::from_rgba8(20, 20, 20, 255));
                    pixmap.fill_path(&path, &paint, FillRule::Winding, ts, None);
                }
            }
        }
    }

    println!("\ntiny-skia: same content, full-page pixmap vs clipped tile pixmap\n");
    println!(
        "{:>11}  {:>10}  {:>10}  {:>8}",
        "full px", "full ms", "tile ms", "speedup"
    );
    for (full_w, full_h) in [(2381u32, 3368u32), (4134, 5846)] {
        let (tile_w, tile_h) = (VIEWPORT_W, VIEWPORT_H);
        let x = (full_w - tile_w) / 2;
        let y = (full_h - tile_h) / 2;

        let full_ms = best_ms(
            || {
                let mut pixmap = Pixmap::new(full_w, full_h).unwrap();
                pixmap.fill(Color::WHITE);
                draw(&mut pixmap, Transform::identity(), full_w, full_h);
                std::hint::black_box(&pixmap);
            },
            3,
        );
        let tile_ms = best_ms(
            || {
                let mut pixmap = Pixmap::new(tile_w, tile_h).unwrap();
                pixmap.fill(Color::WHITE);
                // Exactly what a clipped render does: same scale, origin shifted.
                let ts = Transform::identity().post_translate(-(x as f32), -(y as f32));
                draw(&mut pixmap, ts, full_w, full_h);
                std::hint::black_box(&pixmap);
            },
            3,
        );
        println!(
            "{:>11}  {full_ms:>9.1}  {tile_ms:>9.1}  {:>7.1}x",
            format!("{full_w}x{full_h}"),
            full_ms / tile_ms
        );
    }
}

/// Clipping makes a tile's cost independent of *resolution*, but not
/// necessarily of *content*: `render_frame` still walks every item on the page
/// and asks whether it lands on the canvas. This measures what a page densely
/// packed by a `#for` loop does to a fixed viewport tile — i.e. whether the
/// ~3ms figure survives pathological documents, or whether a slow render can
/// still come back (which is what would justify cancellable renders).
#[test]
#[ignore]
fn tile_cost_versus_page_content_density() {
    let cases: &[(&str, &str)] = &[
        ("plain A4 text", "= A Typical Document\n#lorem(400)"),
        (
            "dense glyphs, one A4 page",
            "#set text(size: 2pt)\n#lorem(20000)",
        ),
        (
            "for-loop table, tall auto page",
            "#set page(height: auto)\n\
             #table(columns: 8, ..range(20000).map(i => [#i]).flatten())",
        ),
        (
            "for-loop shapes, tall auto page",
            "#set page(height: auto)\n\
             #for i in range(20000) [#box(width: 3pt, height: 3pt, fill: red) ]",
        ),
        (
            "nested groups, tall auto page",
            "#set page(height: auto)\n\
             #for i in range(4000) [\n\
               #box(clip: true, width: 20pt, height: 6pt)[#box(fill: blue)[#text(4pt)[x#i]]]\n\
             ]",
        ),
    ];

    println!("\nviewport tile {VIEWPORT_W}x{VIEWPORT_H}px at 288 dpi\n");
    println!(
        "{:<32} {:>7} {:>13} {:>10} {:>10} {:>10}",
        "document", "pages", "page px", "tile ms", "walk ms", "visible%"
    );

    for (label, source) in cases {
        let s = session();
        let result = s.compile((*source).to_owned());
        if !result.success {
            println!("{label:<32} FAILED TO COMPILE");
            continue;
        }
        let page = &result.pages[0];
        let scale = 288.0 / 72.0;
        let full_w = (page.width_pt * scale).round() as u32;
        let full_h = (page.height_pt * scale).round() as u32;
        let tile_w = VIEWPORT_W.min(full_w);
        let tile_h = VIEWPORT_H.min(full_h);
        // Sample from the middle of the page, so the tile is surrounded by
        // content it must consider and reject rather than sitting past the end.
        let x = (full_w.saturating_sub(tile_w)) / 2;
        let y = (full_h.saturating_sub(tile_h)) / 2;

        let ms = best_ms(
            || {
                s.render_page_region(
                    result.generation,
                    0,
                    x,
                    y,
                    tile_w,
                    tile_h,
                    full_w,
                    full_h,
                    0xffffffff,
                )
                .unwrap();
            },
            5,
        );

        // A 1x1 tile draws essentially nothing, so it isolates the fixed cost
        // of walking the page's items and rejecting them.
        let walk_ms = best_ms(
            || {
                s.render_page_region(result.generation, 0, x, y, 1, 1, full_w, full_h, 0xffffffff)
                    .unwrap();
            },
            5,
        );

        let full_px = u64::from(full_w) * u64::from(full_h);
        let tile_px = u64::from(tile_w) * u64::from(tile_h);
        println!(
            "{label:<32} {:>7} {:>13} {ms:>9.1} {walk_ms:>9.1} {:>9.2}%",
            result.pages.len(),
            format!("{full_w}x{full_h}"),
            (tile_px as f64) / (full_px as f64) * 100.0,
        );
    }
}
