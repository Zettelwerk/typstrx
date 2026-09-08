## 0.1.0

Initial release.

- Compile Typst source strings with the embedded Rust Typst compiler,
  including diagnostics with source locations
- Viewport-based high-resolution page rendering
- `TypstViewer` widget with pan/zoom, text selection, and links
- Embedded default fonts + custom font registration
- `@preview` package downloads with local caching
- `TypstViewerController.currentRasterScale`/`currentRasterDpi`/
  `lastRender`/`cacheBytes` for reading back the actual on-screen
  rasterization resolution and render cost live
- `TypstViewerParams.maxRenderDpi`/`previewDpi` (DPI-based; replace the
  earlier pixels-per-point `maxRenderScale`/`previewScaleCap`) to size
  rasterization quality directly in DPI. `previewDpi` is now a fixed
  baseline (rasterized regardless of current zoom, like pdfrx's
  `onePassRenderingScaleThreshold`) rather than an adaptive cap; the
  zoom-adaptive tile tier (`maxRenderDpi`) takes over once the current
  zoom needs more resolution than that baseline provides
- `TypstViewerParams.fixedRasterDpi` to pin every render (both tiers) to a
  constant DPI regardless of zoom, for comparing the fixed-quality vs.
  adaptive-quality rasterization models hands-on
- `TypstViewerParams.tileScaleFactor` to scale the zoom-adaptive tile
  resolution up or down relative to what the current zoom strictly needs
- Clipped rasterization: a tile is now rendered straight into a tile-sized
  buffer instead of rasterizing the whole page and cropping, via a vendored,
  modified copy of `typst-render` (`third_party/typst-render-clip`, Apache-2.0
  — see its `NOTICE.md`). Rendering the visible window now costs roughly what
  the viewport costs rather than growing with the page area times the square of
  the zoom: measured on a text-heavy A4 page, a viewport tile went from 7ms at
  144 DPI / 22ms at 500 DPI / 103ms at 720 DPI to ~3ms flat across that range.
  The `RenderTooLarge` pixel budget now bounds the tile actually allocated
  rather than the page's virtual size, so an extreme zoom no longer fails
- `TypstViewerParams.maxRenderDpi` now defaults to `576.0` (was `288.0`), and
  is a quality ceiling rather than a limit keeping render cost bounded
- `TypstViewerParams.renderDelay` now defaults to 16ms (was 80ms), since a
  discarded tile render no longer costs tens of milliseconds
- The visible hi-res tile is now rendered *before* neighbouring pages'
  full-page previews, instead of queueing behind them
- Hi-res tiles now survive leaving the viewport and are evicted by the image
  cache budget (farthest page first) like previews, so panning back to a page
  reuses its tile instead of re-rendering it
- Adaptive tile DPI snaps up to discrete rungs, so a range of zoom levels
  reuses one cached tile instead of re-rendering on every gesture frame
