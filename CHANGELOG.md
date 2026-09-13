## 0.1.0

Initial release.

- Compile Typst source strings with the embedded Rust Typst compiler,
  including diagnostics with source locations
- Viewport-based high-resolution page rendering
- `TypstViewer` widget with pan/zoom, text selection, and links
- Embedded default fonts + custom font registration
- `@preview` package downloads with local caching
- `TypstDocument.exportPdf({tagged})` for generation-checked vector PDF
  export. `tagged` defaults to `true` (matching typst-pdf's own default,
  writing a structure tree for accessibility/PDF-UA); pass `false` for an
  embedded fragment that will be stamped into another document, whose own
  structure tree wouldn't describe the final file
- `TypstPageView`, a host-controlled, single-page, transparent Typst
  surface for canvases/notebooks that embed rendered content inline
  instead of showing a paginated document — sized to its compiled content,
  with no pan/zoom of its own
- `TypstSession.compileFragment`/`updateFragmentSource` +
  `TypstFragmentOptions` to compile Typst source as a content-sized,
  transparent embedded page; diagnostics and editor analysis offsets are
  mapped back to the caller's own source, so a host never accounts for the
  generated page preamble
- `TypstTextSelection`/`TypstTextPosition`/`TypstTextSelectionRect` and
  `TypstViewerController.selection`/`TypstViewerParams.onSelectionChanged`
  so a host can read or react to a rendered-text selection directly
  instead of only copying it
- `TypstViewerParams.pageColor`/`showSelectionToolbar`/`enableNavigation`/
  `rasterBackgroundColor`, letting a host disable typstrx's own page
  background, copy toolbar, and pan/zoom gestures when it's driving those
  itself (used by `TypstPageView`)
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
