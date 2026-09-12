//! Rasterization of compiled pages.
//!
//! Region renders go straight into a tile-sized pixmap: the page transform is
//! shifted by the tile origin so only the requested window is rasterized (see
//! `typst_render_clip::render_tile`). The cost of drawing what is on screen
//! therefore scales with the viewport, not with the page area times the square
//! of the zoom, which is what lets the viewer keep sharpening as the user zooms
//! in without a resolution ceiling.

use typst::utils::Scalar;
use typst_layout::Page;
use typst_render_clip::RenderOptions;

use crate::api::types::{RenderedRegion, TypstrxError};

/// Upper bound on the pixel count of a single rendered tile.
///
/// Now that only the tile is allocated, this bounds real memory use rather than
/// standing in for the page's virtual size, which costs nothing. The number is
/// unchanged from the full-page budget it replaces (64 MPix RGBA = 256 MiB) so
/// that whole-page preview renders, which legitimately ask for a tile the size
/// of the page, keep the same ceiling they had.
const MAX_TILE_PIXELS: u64 = 64_000_000;

/// Renders the window `(x, y, width, height)` (in pixels) out of the page
/// rasterized at a virtual full size of `full_width` × `full_height` pixels.
///
/// The result is premultiplied RGBA8888, ready for Flutter's
/// `PixelFormat.rgba8888`. `background_argb` covers transparent parts of the
/// page and its alpha is preserved.
#[allow(clippy::too_many_arguments)] // deliberate region-API shape
pub fn render_region(
    page: &Page,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    full_width: u32,
    full_height: u32,
    background_argb: u32,
) -> Result<RenderedRegion, TypstrxError> {
    if width == 0 || height == 0 || full_width == 0 || full_height == 0 {
        return Err(TypstrxError::RenderTooLarge {
            message: "render size must be non-zero".to_owned(),
        });
    }
    if u64::from(width) * u64::from(height) > MAX_TILE_PIXELS {
        return Err(TypstrxError::RenderTooLarge {
            message: format!(
                "tile render of {width}x{height} px exceeds the \
                 {MAX_TILE_PIXELS} pixel budget"
            ),
        });
    }

    let page_width_pt = page.frame.width().to_pt();
    if page_width_pt <= 0.0 {
        return Err(TypstrxError::RenderTooLarge {
            message: "page has zero width".to_owned(),
        });
    }
    let pixel_per_pt = f64::from(full_width) / page_width_pt;

    let opts = RenderOptions {
        pixel_per_pt: Scalar::new(pixel_per_pt),
        ..Default::default()
    };

    // The background goes down inside the tile render rather than as a second
    // buffer to compose against: it only ever shows where the tile overhangs
    // the page edge (rounding can push a request a pixel or two past it) or
    // where the page fill is not opaque.
    let a = ((background_argb >> 24) & 0xff) as u8;
    let r = ((background_argb >> 16) & 0xff) as u8;
    let g = ((background_argb >> 8) & 0xff) as u8;
    let b = (background_argb & 0xff) as u8;
    let background = tiny_skia::Color::from_rgba8(r, g, b, a);

    let tile = typst_render_clip::render_tile(
        page,
        &opts,
        x as i32,
        y as i32,
        width,
        height,
        Some(background),
    )
    .ok_or_else(|| TypstrxError::RenderTooLarge {
        message: format!("cannot allocate {width}x{height} px tile"),
    })?;

    Ok(RenderedRegion {
        width,
        height,
        pixels: tile.take(),
    })
}

#[cfg(test)]
mod tests {
    //! The safety net for the vendored `typst-render-clip`.
    //!
    //! Clipped rendering is only sound if a tile matches the same window cropped
    //! out of an upstream whole-page render. An *untranslated* tile must match
    //! it bit for bit. A translated one cannot: shifting the transform by the
    //! tile origin is exact in real arithmetic but not in f32, so glyph
    //! antialiasing lands a unit off here and there, and gradients — whose
    //! texture is sampled with `FilterQuality::Nearest` — occasionally pick the
    //! neighbouring texel. Both are invisible.
    //!
    //! What these tests are really looking for is structural damage: a glyph
    //! culled that should have been drawn, a gradient sized from the tile
    //! instead of the page (`State::size` feeds `RelativeTo::Parent` sizing and
    //! must stay the full page), a misplaced origin. Any of those move pixels by
    //! a lot, so the bound that matters is on *magnitude*, not on how many
    //! pixels differ — antialiasing noise is unbounded in count but never more
    //! than a unit or two deep.

    use typst_layout::Page;

    use super::*;
    use crate::api::session::TypstSession;
    use crate::api::types::SessionOptions;

    /// No pixel may differ by more than this regardless of content: past here a
    /// difference is structural, not rounding.
    const HARD_DELTA: i32 = 32;

    fn session() -> TypstSession {
        TypstSession::create(SessionOptions {
            package_cache_dir: None,
            allow_package_download: false,
        })
    }

    /// Crops `(x, y, w, h)` out of an upstream whole-page render — exactly what
    /// `render_region` did before clipping.
    fn upstream_crop(page: &Page, pixel_per_pt: f64, x: u32, y: u32, w: u32, h: u32) -> Vec<u8> {
        let full = typst_render::render(
            page,
            &typst_render::RenderOptions {
                pixel_per_pt: Scalar::new(pixel_per_pt),
                ..Default::default()
            },
        );
        let mut canvas = tiny_skia::Pixmap::new(w, h).unwrap();
        canvas.draw_pixmap(
            -(x as i32),
            -(y as i32),
            full.as_ref(),
            &tiny_skia::PixmapPaint::default(),
            tiny_skia::Transform::identity(),
            None,
        );
        canvas.take()
    }

    fn clipped(page: &Page, pixel_per_pt: f64, x: u32, y: u32, w: u32, h: u32) -> Vec<u8> {
        typst_render_clip::render_tile(
            page,
            &RenderOptions {
                pixel_per_pt: Scalar::new(pixel_per_pt),
                ..Default::default()
            },
            x as i32,
            y as i32,
            w,
            h,
            None,
        )
        .unwrap()
        .take()
    }

    /// Asserts tiles match upstream, allowing per-channel differences up to
    /// `max_delta`. Pass the smallest value the content can achieve: for
    /// gradient-free content that is 2 (antialiasing rounding), which is tight
    /// enough that a missing or displaced glyph — a delta in the hundreds —
    /// cannot hide behind it.
    fn assert_tiles_match(source: &str, label: &str, max_delta: i32) {
        let s = session();
        let result = s.compile(source.to_owned());
        assert!(
            result.success,
            "{label} failed to compile: {:?}",
            result
                .diagnostics
                .iter()
                .map(|d| &d.message)
                .collect::<Vec<_>>()
        );

        s.with_page(0, |page| {
            let page_w_pt = page.frame.width().to_pt();
            let page_h_pt = page.frame.height().to_pt();

            for dpi in [144.0_f64, 288.0, 500.0] {
                let pixel_per_pt = dpi / 72.0;
                let full_w = (page_w_pt * pixel_per_pt).round() as u32;
                let full_h = (page_h_pt * pixel_per_pt).round() as u32;

                // Origins include (0,0), an odd offset, and a window well inside
                // the page, so a bug that only appears once the origin is
                // non-zero cannot hide.
                for &(x, y, w, h) in &[
                    (0u32, 0u32, 300u32, 200u32),
                    (137, 211, 400, 300),
                    (full_w / 3, full_h / 2, 500, 400),
                ] {
                    if x + w > full_w || y + h > full_h {
                        continue;
                    }
                    let expected = upstream_crop(page, pixel_per_pt, x, y, w, h);
                    let actual = clipped(page, pixel_per_pt, x, y, w, h);
                    assert_eq!(expected.len(), actual.len());

                    // Nothing about the restructuring may change a whole-page
                    // render, so an untranslated tile has to be exact.
                    if x == 0 && y == 0 {
                        assert!(
                            expected == actual,
                            "{label}: untranslated tile differs from upstream at {dpi} dpi"
                        );
                        continue;
                    }

                    let worst = expected
                        .iter()
                        .zip(actual.iter())
                        .map(|(a, b)| (*a as i32 - *b as i32).abs())
                        .max()
                        .unwrap_or(0);
                    let over: usize = expected
                        .chunks(4)
                        .zip(actual.chunks(4))
                        .filter(|(a, b)| {
                            a.iter()
                                .zip(b.iter())
                                .any(|(p, q)| (*p as i32 - *q as i32).abs() > max_delta)
                        })
                        .count();
                    let pixels = (w * h) as usize;
                    let over_share = over as f64 / pixels as f64;

                    // Isolated pixels can exceed the antialiasing band when a
                    // glyph edge lands right on a rounding boundary, so allow a
                    // vanishing share of them but nothing systematic: dropping
                    // even one glyph paints hundreds of pixels hundreds of
                    // levels off, which breaks both bounds at once.
                    assert!(
                        over_share < 0.0005 && worst <= HARD_DELTA,
                        "{label}: clipped tile diverges from upstream crop at {dpi} dpi, \
                         window ({x},{y}) {w}x{h}: {over} of {pixels} pixels ({:.4}%) \
                         differ by more than {max_delta}, max channel delta {worst}",
                        over_share * 100.0,
                    );
                }
            }
        })
        .expect("no compiled page");
    }

    #[test]
    fn text_page_tiles_match_upstream() {
        assert_tiles_match("= A Typical Document\n#lorem(400)", "text", 2);
    }

    #[test]
    fn math_page_tiles_match_upstream() {
        // Large glyph variants (integrals, sums, radicals) reach far past the em
        // square — exactly what the glyph culling must not wrongly reject.
        assert_tiles_match(
            "#for i in range(20) [\n\
             $ sum_(k=1)^n integral_0^oo sqrt((x^#i + 1)/(y - #i)) dif x $\n]",
            "math",
            2,
        );
    }

    #[test]
    fn table_page_tiles_match_upstream() {
        assert_tiles_match(
            "#table(columns: 4, ..range(80).map(i => [#i]).flatten())\n#lorem(100)",
            "table",
            2,
        );
    }

    #[test]
    fn gradient_page_tiles_match_upstream() {
        // Gradients are where sizing from the tile instead of the page would
        // show up as a seam. Their texture is sampled with nearest-neighbour
        // filtering, so a sub-pixel shift can pick the adjacent texel; a
        // wrongly *sized* gradient would instead be wrong nearly everywhere.
        assert_tiles_match(
            "#set page(fill: gradient.linear(red, blue))\n\
             #rect(width: 100%, height: 4cm, fill: gradient.radial(yellow, green))\n\
             #circle(radius: 3cm, fill: gradient.linear(purple, orange))\n\
             #lorem(60)",
            "gradient",
            16,
        );
    }

    #[test]
    fn transparent_background_preserves_alpha() {
        let s = session();
        let result = s.compile(
            "#set page(width: 100pt, height: 100pt, margin: 0pt, fill: none)\n\
             #rect(width: 20pt, height: 20pt, fill: red)"
                .to_owned(),
        );
        assert!(result.success, "transparent fragment failed to compile");
        s.with_page(0, |page| {
            let image = render_region(page, 0, 0, 100, 100, 100, 100, 0).unwrap();
            let pixel = |x: usize, y: usize| &image.pixels[(y * 100 + x) * 4..][..4];
            assert_eq!(pixel(90, 90), &[0, 0, 0, 0]);
            assert_eq!(pixel(10, 10)[3], 255);
        })
        .expect("no compiled page");
    }
}
