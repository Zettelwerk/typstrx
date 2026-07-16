//! Rasterization of compiled pages.
//!
//! `typst-render` can only rasterize whole pages, so a region render currently
//! rasterizes the full page at the requested scale and crops the requested
//! window out of it. The API is region-shaped (like pdfrx's `render`) so the
//! backend can later switch to true sub-region rendering without breaking
//! callers.

use typst_layout::Page;
use typst::utils::Scalar;
use typst_render::RenderOptions;

use crate::api::types::{RenderedRegion, TypstrxError};

/// Upper bound on the whole-page pixel count for a single render call. Guards
/// against runaway memory use at extreme zoom (64 MPix RGBA = 256 MiB).
const MAX_FULL_PIXELS: u64 = 64_000_000;

/// Renders the window `(x, y, width, height)` (in pixels) out of the page
/// rasterized at a virtual full size of `full_width` × `full_height` pixels.
///
/// The result is straight (non-premultiplied) RGBA8888. The page is composited
/// over `background_argb`, whose alpha is forced to opaque; with an opaque
/// background, premultiplied and straight RGBA are identical, so no conversion
/// pass is needed.
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
    if u64::from(full_width) * u64::from(full_height) > MAX_FULL_PIXELS {
        return Err(TypstrxError::RenderTooLarge {
            message: format!(
                "full page render of {full_width}x{full_height} px exceeds the \
                 {MAX_FULL_PIXELS} pixel budget; lower the render scale"
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

    let full = typst_render::render(
        page,
        &RenderOptions {
            pixel_per_pt: Scalar::new(pixel_per_pt),
            ..Default::default()
        },
    );

    let a = 0xff;
    let r = ((background_argb >> 16) & 0xff) as u8;
    let g = ((background_argb >> 8) & 0xff) as u8;
    let b = (background_argb & 0xff) as u8;

    let mut canvas = tiny_skia::Pixmap::new(width, height).ok_or_else(|| {
        TypstrxError::RenderTooLarge {
            message: format!("cannot allocate {width}x{height} px tile"),
        }
    })?;
    canvas.fill(tiny_skia::Color::from_rgba8(r, g, b, a));
    canvas.draw_pixmap(
        -(x as i32),
        -(y as i32),
        full.as_ref(),
        &tiny_skia::PixmapPaint::default(),
        tiny_skia::Transform::identity(),
        None,
    );

    Ok(RenderedRegion {
        width,
        height,
        pixels: canvas.take(),
    })
}
