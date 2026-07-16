//! Extraction of text and link geometry from compiled pages.
//!
//! Walks a page's frame tree and produces, per page:
//! - `full_text` in visual reading order (top-to-bottom, left-to-right),
//!   with `\n` between lines,
//! - one bounding rect per UTF-16 code unit of `full_text` (so Dart string
//!   indices map 1:1 onto rects),
//! - one fragment per text run (contiguous range of `full_text` + bounds),
//! - link rects with their resolved destinations.

use typst::introspection::Location;
use typst::layout::{Frame, FrameItem, Point, Size, Transform};
use typst::model::Destination;
use typst_layout::PagedDocument;

use crate::api::types::{LinkData, PageTextData, RectPt, TextFragmentData};

/// A text run collected during traversal, in page coordinates (pt, y-down).
struct RawFragment {
    text: String,
    /// One rect per UTF-16 code unit of `text`.
    char_rects: Vec<RectPt>,
    bounds: RectPt,
    baseline_y: f64,
}

pub fn extract_page_text(document: &PagedDocument, page_index: usize) -> PageTextData {
    let page = &document.pages()[page_index];
    let mut fragments = Vec::new();
    let mut links = Vec::new();
    walk_frame(
        document,
        &page.frame,
        Transform::identity(),
        &mut fragments,
        &mut links,
    );

    // Visual reading order: primary by baseline, secondary by x position.
    fragments.sort_by(|a, b| {
        (a.baseline_y, a.bounds.left)
            .partial_cmp(&(b.baseline_y, b.bounds.left))
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let mut full_text = String::new();
    let mut char_rects = Vec::new();
    let mut out_fragments = Vec::new();
    let mut utf16_len: u32 = 0;
    let mut previous_baseline: Option<f64> = None;

    for fragment in fragments {
        let fragment_units = fragment.char_rects.len() as u32;
        if fragment_units == 0 {
            continue;
        }
        // Line break between fragments on clearly different baselines. The
        // newline belongs to the previous fragment (zero-width rect at its
        // end) so every code unit of `full_text` stays covered by a fragment.
        if let Some(prev) = previous_baseline {
            if (fragment.baseline_y - prev).abs() > 0.1 {
                full_text.push('\n');
                let anchor = char_rects
                    .last()
                    .map(|r: &RectPt| RectPt {
                        left: r.right,
                        top: r.top,
                        right: r.right,
                        bottom: r.bottom,
                    })
                    .unwrap_or(RectPt {
                        left: 0.0,
                        top: 0.0,
                        right: 0.0,
                        bottom: 0.0,
                    });
                char_rects.push(anchor);
                if let Some(last) = out_fragments.last_mut() {
                    let last: &mut TextFragmentData = last;
                    last.length += 1;
                }
                utf16_len += 1;
            }
        }
        previous_baseline = Some(fragment.baseline_y);

        out_fragments.push(TextFragmentData {
            index: utf16_len,
            length: fragment_units,
            bounds: fragment.bounds.clone(),
        });
        full_text.push_str(&fragment.text);
        char_rects.extend(fragment.char_rects);
        utf16_len += fragment_units;
    }

    PageTextData {
        full_text,
        char_rects,
        fragments: out_fragments,
        links,
    }
}

fn walk_frame(
    document: &PagedDocument,
    frame: &Frame,
    transform: Transform,
    fragments: &mut Vec<RawFragment>,
    links: &mut Vec<LinkData>,
) {
    for (pos, item) in frame.items() {
        match item {
            FrameItem::Group(group) => {
                let child = transform
                    .pre_concat(Transform::translate(pos.x, pos.y))
                    .pre_concat(group.transform);
                walk_frame(document, &group.frame, child, fragments, links);
            }
            FrameItem::Text(text) => {
                if let Some(fragment) = extract_text_item(text, *pos, transform) {
                    fragments.push(fragment);
                }
            }
            FrameItem::Link(dest, size) => {
                links.push(extract_link(document, dest, *pos, *size, transform));
            }
            FrameItem::Shape(..) | FrameItem::Image(..) | FrameItem::Tag(..) => {}
        }
    }
}

fn extract_text_item(
    item: &typst::text::TextItem,
    pos: Point,
    transform: Transform,
) -> Option<RawFragment> {
    if item.text.is_empty() {
        return None;
    }
    let size = item.size;
    let metrics = item.font.metrics();
    let ascent = metrics.ascender.at(size).to_pt();
    let descent = metrics.descender.at(size).to_pt(); // typically negative

    // Per-UTF-8-byte horizontal extents within the run, resolved from glyph
    // advances. Ligatures map one glyph to several bytes; the glyph's width
    // is split evenly across its characters below.
    let byte_len = item.text.len();
    let mut byte_start_x = vec![f64::NAN; byte_len + 1];
    let mut byte_end_x = vec![f64::NAN; byte_len + 1];
    let mut cursor = 0.0f64;
    for glyph in &item.glyphs {
        let advance = glyph.x_advance.at(size).to_pt();
        let start = glyph.range.start as usize;
        let end = glyph.range.end as usize;
        let x0 = cursor;
        let x1 = cursor + advance;
        for b in start..end.min(byte_len) {
            if byte_start_x[b].is_nan() || x0 < byte_start_x[b] {
                byte_start_x[b] = x0;
            }
            if byte_end_x[b].is_nan() || x1 > byte_end_x[b] {
                byte_end_x[b] = x1;
            }
        }
        cursor = x1;
    }
    let total_width = cursor;

    // Emit one rect per UTF-16 code unit, splitting multi-char glyph spans
    // evenly and repeating the rect for surrogate pairs.
    let mut char_rects = Vec::new();
    let baseline = pos.y.to_pt();
    let top = baseline - ascent;
    let bottom = baseline - descent;
    let origin_x = pos.x.to_pt();

    // Group consecutive chars that share one glyph span (identical extents).
    let chars: Vec<(usize, char)> = item.text.char_indices().collect();
    let mut i = 0;
    while i < chars.len() {
        let (byte, _) = chars[i];
        let x0 = byte_start_x[byte];
        let x1 = byte_end_x[byte];
        let mut j = i + 1;
        while j < chars.len() {
            let (b, _) = chars[j];
            if byte_start_x[b].is_nan() || (byte_start_x[b] == x0 && byte_end_x[b] == x1) {
                j += 1;
            } else {
                break;
            }
        }
        let group = &chars[i..j];
        let (x0, x1) = if x0.is_nan() { (0.0, 0.0) } else { (x0, x1) };
        let step = (x1 - x0) / group.len() as f64;
        for (k, (_, c)) in group.iter().enumerate() {
            let left = origin_x + x0 + step * k as f64;
            let right = origin_x + x0 + step * (k + 1) as f64;
            let rect = transformed_rect(left, top, right, bottom, transform);
            for _ in 0..c.len_utf16() {
                char_rects.push(rect.clone());
            }
        }
        i = j;
    }

    let bounds = transformed_rect(origin_x, top, origin_x + total_width, bottom, transform);
    let baseline_y = Point::new(pos.x, pos.y).transform(transform).y.to_pt();

    Some(RawFragment {
        text: item.text.to_string(),
        char_rects,
        bounds,
        baseline_y,
    })
}

fn extract_link(
    document: &PagedDocument,
    dest: &Destination,
    pos: Point,
    size: Size,
    transform: Transform,
) -> LinkData {
    let rect = transformed_rect(
        pos.x.to_pt(),
        pos.y.to_pt(),
        (pos.x + size.x).to_pt(),
        (pos.y + size.y).to_pt(),
        transform,
    );
    let mut link = LinkData {
        rect,
        url: None,
        dest_page: None,
        dest_x_pt: None,
        dest_y_pt: None,
    };
    match dest {
        Destination::Url(url) => link.url = Some(url.as_str().to_string()),
        Destination::Position(position) => set_position(&mut link, position),
        Destination::Location(location) => {
            if let Some(position) = resolve_location(document, *location) {
                set_position(&mut link, &position);
            }
        }
    }
    link
}

fn set_position(link: &mut LinkData, position: &typst::introspection::PagedPosition) {
    link.dest_page = Some(position.page.get() as u32);
    link.dest_x_pt = Some(position.point.x.to_pt());
    link.dest_y_pt = Some(position.point.y.to_pt());
}

fn resolve_location(
    document: &PagedDocument,
    location: Location,
) -> Option<typst::introspection::PagedPosition> {
    document.introspector().position(location)
}

/// Bounding box of an axis-aligned rect after applying `transform`, in pt
/// with a y-down top-left origin (`top <= bottom`).
fn transformed_rect(left: f64, top: f64, right: f64, bottom: f64, transform: Transform) -> RectPt {
    if transform == Transform::identity() {
        return RectPt {
            left,
            top,
            right,
            bottom,
        };
    }
    let abs = typst::layout::Abs::pt;
    let corners = [
        Point::new(abs(left), abs(top)).transform(transform),
        Point::new(abs(right), abs(top)).transform(transform),
        Point::new(abs(left), abs(bottom)).transform(transform),
        Point::new(abs(right), abs(bottom)).transform(transform),
    ];
    let xs: Vec<f64> = corners.iter().map(|p| p.x.to_pt()).collect();
    let ys: Vec<f64> = corners.iter().map(|p| p.y.to_pt()).collect();
    RectPt {
        left: xs.iter().cloned().fold(f64::INFINITY, f64::min),
        top: ys.iter().cloned().fold(f64::INFINITY, f64::min),
        right: xs.iter().cloned().fold(f64::NEG_INFINITY, f64::max),
        bottom: ys.iter().cloned().fold(f64::NEG_INFINITY, f64::max),
    }
}
