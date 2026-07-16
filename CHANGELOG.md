## 0.1.0

Initial release.

- Compile Typst source strings with the embedded Rust Typst compiler,
  including diagnostics with source locations
- Viewport-based high-resolution page rendering
- `TypstViewer` widget with pan/zoom, text selection, and links
- Embedded default fonts + custom font registration
- `@preview` package downloads with local caching
- `TypstViewerController.currentRasterScale`/`lastRender`/`cacheBytes` for
  reading back the actual on-screen rasterization resolution and render
  cost live
