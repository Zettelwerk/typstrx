//! Rendering of Typst documents into raster images.
//!
//! MODIFIED COPY of `typst-render` 0.15.0 (Apache-2.0, © The Typst Project
//! Developers). See `NOTICE.md` in this directory for the list of changes.
//! Upstream rasterizes whole pages only; this copy adds [`render_tile`], which
//! rasterizes just a pixel window of a page, so the cost of rendering what is
//! on screen scales with the viewport rather than with the page area times the
//! square of the zoom.

mod image;
mod paint;
mod shape;
mod text;

use tiny_skia as sk;
use typst_layout::{Page, PagedDocument};
use typst_library::layout::{
    Abs, Axes, Frame, FrameItem, FrameKind, GroupItem, Point, Sides, Size, Transform,
};
use typst_library::visualize::{Color, Geometry, Paint};
use typst_utils::Scalar;

/// Export a page into a raster image.
///
/// This renders the page at the given number of pixels per point and returns
/// the resulting `tiny-skia` pixel buffer.
#[typst_macros::time(name = "render")]
pub fn render(page: &Page, opts: &RenderOptions) -> sk::Pixmap {
    let (pxw, pxh) = full_page_size(page, opts);
    // Delegated so the whole-page and tile paths cannot drift apart: a tile is
    // exactly this render with a smaller pixmap and a shifted origin.
    render_tile(page, opts, 0, 0, pxw, pxh, None).unwrap()
}

/// The pixel dimensions [`render`] would produce for this page and options.
pub fn full_page_size(page: &Page, opts: &RenderOptions) -> (u32, u32) {
    let bleed = if opts.render_bleed { page.bleed } else { Sides::default() };
    let size = page.frame.size() + bleed.sum_by_axis();
    let pixel_per_pt = opts.pixel_per_pt.get() as f32;
    (
        (pixel_per_pt * size.x.to_f32()).round().max(1.0) as u32,
        (pixel_per_pt * size.y.to_f32()).round().max(1.0) as u32,
    )
}

/// Export a *window* of a page into a raster image.
///
/// Renders the `tile_width` x `tile_height` pixel window whose top-left corner
/// sits at `(x, y)` in the full-page raster that [`render`] would produce at
/// the same [`RenderOptions`] — without allocating or rasterizing the rest of
/// that page. Returns `None` only if the tile pixmap cannot be allocated.
///
/// The result is bit-identical to cropping the same window out of [`render`]'s
/// output, because the tile origin is a whole number of pixels: every primitive
/// keeps the subpixel phase it would have had, so glyph coverage bitmaps and
/// antialiasing are unchanged and only their placement shifts.
///
/// `background` is painted first, under the page fill, for callers compositing
/// a tile onto a surround; pass `None` for upstream's transparent start.
pub fn render_tile(
    page: &Page,
    opts: &RenderOptions,
    x: i32,
    y: i32,
    tile_width: u32,
    tile_height: u32,
    background: Option<sk::Color>,
) -> Option<sk::Pixmap> {
    let bleed = if opts.render_bleed { page.bleed } else { Sides::default() };

    let size = page.frame.size() + bleed.sum_by_axis();
    let pixel_per_pt = opts.pixel_per_pt.get() as f32;

    // The page transform, shifted by the tile origin. `size` deliberately stays
    // the *full page*: it feeds `RelativeTo::Parent` gradient and tiling sizing
    // (see `paint.rs`), which must not change with the window being drawn, or
    // gradients would break at tile seams. `container_transform` picks up the
    // same shift and is inverted consistently there.
    let ts = sk::Transform::from_scale(pixel_per_pt, pixel_per_pt)
        .post_translate(-x as f32, -y as f32);
    let state = State::new(size, ts, pixel_per_pt);

    let mut canvas = sk::Pixmap::new(tile_width, tile_height)?;

    if let Some(background) = background {
        canvas.fill(background);
    }

    if let Some(fill) = page.fill_or_white() {
        if let Paint::Solid(color) = fill {
            canvas.fill(paint::to_sk_color(color.to_process()));
        } else {
            let rect = Geometry::Rect(size).filled(fill);
            shape::render_shape(&mut canvas, state, &rect);
        }
    }

    let state = state.pre_translate(Point { x: bleed.left, y: bleed.top });

    render_frame(&mut canvas, state, &page.frame);

    Some(canvas)
}

/// Export a document with potentially multiple pages into a single raster image.
pub fn render_merged(
    document: &PagedDocument,
    opts: &RenderOptions,
    gap: Abs,
    fill: Option<Color>,
) -> sk::Pixmap {
    let pixmaps: Vec<_> =
        document.pages().iter().map(|page| render(page, opts)).collect();

    let pixel_per_pt = opts.pixel_per_pt.get() as f32;
    let gap = (pixel_per_pt * gap.to_f32()).round() as u32;
    let pxw = pixmaps.iter().map(sk::Pixmap::width).max().unwrap_or_default();
    let pxh = pixmaps.iter().map(|pixmap| pixmap.height()).sum::<u32>()
        + gap * pixmaps.len().saturating_sub(1) as u32;

    let mut canvas = sk::Pixmap::new(pxw, pxh).unwrap();
    if let Some(fill) = fill {
        canvas.fill(paint::to_sk_color(fill.to_process()));
    }

    let mut y = 0;
    for pixmap in pixmaps {
        canvas.draw_pixmap(
            0,
            y as i32,
            pixmap.as_ref(),
            &sk::PixmapPaint::default(),
            sk::Transform::identity(),
            None,
        );

        y += pixmap.height() + gap;
    }

    canvas
}

/// Settings for raster image export.
#[derive(Debug, Clone, Eq, PartialEq, Hash)]
pub struct RenderOptions {
    /// Controls the scale of the rendered output in pixels per typographic
    /// point. By default, a value of `1.0` is used, meaning one pixel is
    /// generated per point. Increasing this value produces higher-resolution
    /// images, while lower values reduce the output size and rendering cost.
    /// This can be useful when adjusting the final image quality for display or
    /// printing purposes.
    pub pixel_per_pt: Scalar,
    /// By default, rendered pages are bounded to the page size. In some
    /// circumstances, such as when preparing documents for print, it may be
    /// desirable to include content beyond these bounds to account for bleed
    /// margins. This field allows expanding the rendered area to include such
    /// bleed.
    pub render_bleed: bool,
}

impl Default for RenderOptions {
    fn default() -> Self {
        Self {
            pixel_per_pt: Scalar::new(2.0),
            render_bleed: false,
        }
    }
}

/// Additional metadata carried through the rendering process.
#[derive(Default, Copy, Clone)]
struct State<'a> {
    /// The transform of the current item.
    transform: sk::Transform,
    /// The transform of the first hard frame in the hierarchy.
    container_transform: sk::Transform,
    /// The mask of the current item.
    mask: Option<&'a sk::Mask>,
    /// The pixel per point ratio.
    pixel_per_pt: f32,
    /// The size of the first hard frame in the hierarchy.
    size: Size,
}

impl<'a> State<'a> {
    fn new(size: Size, transform: sk::Transform, pixel_per_pt: f32) -> Self {
        Self {
            size,
            transform,
            container_transform: transform,
            pixel_per_pt,
            ..Default::default()
        }
    }

    /// Pre translate the current item's transform.
    fn pre_translate(self, pos: Point) -> Self {
        Self {
            transform: self.transform.pre_translate(pos.x.to_f32(), pos.y.to_f32()),
            ..self
        }
    }

    fn pre_scale(self, scale: Axes<Abs>) -> Self {
        Self {
            transform: self.transform.pre_scale(scale.x.to_f32(), scale.y.to_f32()),
            ..self
        }
    }

    /// Pre concat the current item's transform.
    fn pre_concat(self, transform: sk::Transform) -> Self {
        Self {
            transform: self.transform.pre_concat(transform),
            ..self
        }
    }

    /// Sets the current mask.
    ///
    /// If no mask is provided, the parent mask is used.
    fn with_mask(self, mask: Option<&'a sk::Mask>) -> State<'a> {
        State { mask: mask.or(self.mask), ..self }
    }

    /// Sets the size of the first hard frame in the hierarchy.
    fn with_size(self, size: Size) -> Self {
        Self { size, ..self }
    }

    /// Pre concat the container's transform.
    fn pre_concat_container(self, transform: sk::Transform) -> Self {
        Self {
            container_transform: self.container_transform.pre_concat(transform),
            ..self
        }
    }
}

/// Render a frame into the canvas.
fn render_frame(canvas: &mut sk::Pixmap, state: State, frame: &Frame) {
    for (pos, item) in frame.items() {
        match item {
            FrameItem::Group(group) => {
                render_group(canvas, state, *pos, group);
            }
            FrameItem::Text(text) => {
                text::render_text(canvas, state.pre_translate(*pos), text);
            }
            FrameItem::Shape(shape, _) => {
                shape::render_shape(canvas, state.pre_translate(*pos), shape);
            }
            FrameItem::Image(image, size, _) => {
                image::render_image(canvas, state.pre_translate(*pos), image, *size);
            }
            FrameItem::Link(_, _) => {}
            FrameItem::Tag(_) => {}
        }
    }
}

/// Render a group frame with optional transform and clipping into the canvas.
fn render_group(canvas: &mut sk::Pixmap, state: State, pos: Point, group: &GroupItem) {
    let sk_transform = to_sk_transform(&group.transform);
    let state = match group.frame.kind() {
        FrameKind::Soft => state.pre_translate(pos).pre_concat(sk_transform),
        FrameKind::Hard => state
            .pre_translate(pos)
            .pre_concat(sk_transform)
            .pre_concat_container(
                state
                    .transform
                    .post_concat(state.container_transform.invert().unwrap()),
            )
            .pre_concat_container(to_sk_transform(&Transform::translate(pos.x, pos.y)))
            .pre_concat_container(sk_transform)
            .with_size(group.frame.size()),
    };

    let mut mask = state.mask;
    let storage;
    if let Some(clip_curve) = group.clip.as_ref()
        && let Some(path) = shape::convert_curve(clip_curve)
            .and_then(|path| path.transform(state.transform))
    {
        if let Some(mask) = mask {
            let mut mask = mask.clone();
            mask.intersect_path(
                &path,
                sk::FillRule::default(),
                true,
                sk::Transform::default(),
            );
            storage = mask;
        } else {
            let pxw = canvas.width();
            let pxh = canvas.height();
            let Some(mut mask) = sk::Mask::new(pxw, pxh) else {
                // Fails if clipping rect is empty. In that case we just
                // clip everything by returning.
                return;
            };

            mask.fill_path(
                &path,
                sk::FillRule::default(),
                true,
                sk::Transform::default(),
            );
            storage = mask;
        };

        mask = Some(&storage);
    }

    render_frame(canvas, state.with_mask(mask), &group.frame);
}

fn to_sk_transform(transform: &Transform) -> sk::Transform {
    let Transform { sx, ky, kx, sy, tx, ty } = *transform;
    sk::Transform::from_row(
        sx.get() as _,
        ky.get() as _,
        kx.get() as _,
        sy.get() as _,
        tx.to_f32(),
        ty.to_f32(),
    )
}

/// Additional methods for [`Abs`].
trait AbsExt {
    /// Convert to a number of points as f32.
    fn to_f32(self) -> f32;
}

impl AbsExt for Abs {
    fn to_f32(self) -> f32 {
        self.to_pt() as f32
    }
}
