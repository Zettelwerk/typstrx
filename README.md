# typstrx

A [Typst](https://typst.app) document viewer for Flutter, in the spirit of
[pdfrx](https://pub.dev/packages/pdfrx).

`typstrx` embeds the native Rust [Typst compiler](https://github.com/typst/typst):
you hand it a string of Typst source, it compiles the document (incrementally,
thanks to Typst's built-in memoization), rasterizes pages in high resolution —
only the part currently visible in the viewport — and exposes viewer widgets
with text selection and tappable links, backed by text/link geometry extracted
from the compiled document.

> **Status: work in progress.** APIs may change before 1.0.

## Features

- Compile Typst source strings to paged documents, with diagnostics
  (errors/warnings with source locations)
- High-resolution, viewport-based partial page rendering (only the visible
  window of each page is rasterized at high zoom)
- `TypstViewer` widget with pan/zoom, text selection, and link navigation
- Live recompilation while the source changes (debounced, flicker-free)
- Embedded default fonts (Libertinus, New Computer Modern Math, DejaVu Sans
  Mono) plus an API to register custom font bytes
- `@preview` Typst package support with on-demand downloads and local caching

## Platforms

| Platform | Status |
|---|---|
| Linux | Supported |
| Android | Supported |
| iOS / macOS / Windows | Scaffolded, untested |
| Web | Not supported yet |

## Requirements

The Rust crate embedded in this package is compiled when the consuming app is
built (via [cargokit](https://github.com/irondash/cargokit)). You need:

- A [Rust toolchain](https://rustup.rs) (`rustup`)
- For Android: NDK r26 or newer, plus the Rust targets for your ABIs, e.g.
  `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`

## Quick start

```dart
import 'package:typstrx/typstrx.dart';

Future<void> main() async {
  await Typstrx.init();
  final session = await TypstSession.create();
  runApp(MaterialApp(home: TypstViewer(session: session)));
  session.updateSource('= Hello, *world*!');
}
```

See `example/` for a full split-view editor + viewer demo.

## Custom fonts and project files

```dart
// Register extra font faces (TTF/OTF bytes) — available on the next compile.
await session.registerFont(await File('MyFont.ttf').readAsBytes());

// Provide in-memory project files that the source can reference.
await session.setFile('/images/logo.png', logoBytes);
session.updateSource('#image("/images/logo.png")');
```

`@preview` imports (Typst Universe packages) download on demand into
`TypstSessionOptions.packageCacheDir` (pass an app-specific directory on
mobile; cached packages work offline).

## Working with the document API directly

```dart
final result = await session.compile('= Hi');
final page = result.document!.pages.first;      // sizes in points
final image = await page.render(fullWidth: page.width * 2); // RGBA pixels
final text = await page.loadStructuredText();   // text + char rects
final links = await page.loadLinks();           // URL / internal dests
```

## Roadmap

- Text search widget (the text model already supports `allMatches`-style search)
- Scroll thumbs, facing-page layouts, selection magnifier
- `SelectionArea` integration
- Precompiled Rust binaries (no consumer Rust toolchain needed)
- True sub-region rendering backend (typst-svg + resvg) for very high zoom
- Web support

## License

Apache-2.0. The Typst compiler is likewise Apache-2.0 licensed.
`third_party/typst-render-clip` vendors a modified copy of Typst's
`typst-render` crate (also Apache-2.0); see its
[`NOTICE.md`](third_party/typst-render-clip/NOTICE.md) for the change list,
as required by section 4(b) of the license. `typstrx` is not affiliated with
or endorsed by the Typst project.
