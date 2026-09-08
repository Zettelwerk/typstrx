# typst-render-clip

A **modified copy** of [`typst-render`](https://github.com/typst/typst) version
0.15.0.

Copyright © The Typst Project Developers.
Licensed under the Apache License, Version 2.0 — see [`LICENSE`](LICENSE).

This directory is a derivative work distributed under the terms of that
license. Section 4(b) requires modified files to carry prominent notices stating
that they were changed; the changed files below say so at the point of change,
and this file records the full set.

## Why it exists

Upstream `typst-render` rasterizes whole pages only. A document viewer needs the
part of a page that is on screen, so rendering a viewport-sized window meant
rasterizing the entire page at the target resolution and cropping — making the
cost grow with the page area times the square of the zoom, and forcing a
resolution ceiling to keep it bounded.

Measured on a text-heavy A4 page, a viewport-sized tile cost 7ms at 144 DPI
rising to 22ms at 500 DPI and 103ms at 720 DPI, of which all but a few
milliseconds was spent on pixels that were then discarded. With the changes
below the same tile costs ~3ms flat across that whole range.

## Changes from upstream 0.15.0

### `src/lib.rs`

- Added `render_tile`, which rasterizes a pixel window of a page directly into a
  tile-sized pixmap. The page transform is shifted by the tile origin
  (`post_translate`) so only the requested window is drawn; `State::size` stays
  the **full page**, because it feeds `RelativeTo::Parent` gradient and tiling
  sizing (`paint.rs`) and must not vary with the window being drawn.
- Added an optional `background` colour, painted under the page fill, so a
  caller compositing a tile onto a surround needs no second buffer.
- Added `full_page_size`, exposing the pixel dimensions `render` would produce.
- `render` now delegates to `render_tile` with a zero origin and the full page
  size, so the whole-page and tile paths cannot drift apart.

### `src/text.rs`

- Added `glyph_may_touch_canvas` and a call to it in `render_text`, rejecting
  glyphs that cannot put ink on the canvas before either glyph path does its
  expensive work — `rasterize` building a coverage bitmap, or `glyph_frame`
  decoding a colour glyph. Upstream relies on `write_bitmap` clamping to the
  canvas, which is free when the canvas is the whole page but wasteful when it
  is a small tile. The test is conservative: it maps all four corners of the
  font's own glyph bounding box, so skew and anisotropic scaling widen the box
  rather than letting a glyph escape it, and a glyph whose font reports no
  bounding box is never skipped.

No other files are modified.

## Verifying the modifications

`rust/src/render.rs` carries tests that render tiles through this crate and
compare them against cropping the same window out of an **upstream**
`typst-render` whole-page render, across text, maths, table and gradient
content at several resolutions and tile origins. Upstream `typst-render` is
kept as a dependency of `typstrx` for exactly that comparison.

An untranslated tile must match upstream bit for bit. A translated one is
allowed to differ by a bounded amount per channel: shifting the transform by the
tile origin is exact in real arithmetic but not in `f32`, so glyph antialiasing
lands a level off here and there, and gradients — whose texture is sampled with
nearest-neighbour filtering — occasionally pick the adjacent texel.

## Upgrading Typst

This copy is pinned to the `typst-*` 0.15.0 crates and uses their internal frame
types, so a Typst upgrade requires re-applying these changes to the matching
`typst-render` release. The changes are small and localised by design. Upstream
gaining a clip or offset parameter of its own would make this directory
unnecessary.
