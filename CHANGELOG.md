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
