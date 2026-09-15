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

![Showcase](https://raw.githubusercontent.com/Zettelwerk/typstrx/refs/heads/main/typstrx-showcase.png "Showcase of demo application")

## Features

- Compile Typst source strings to paged documents, with diagnostics
(errors/warnings with source locations)
- High-resolution, viewport-based partial page rendering (only the visible
window of each page is rasterized at high zoom)
- `TypstViewer` widget with pan/zoom, text selection, and link navigation
- `TypstPageView`, a host-controlled embeddable surface for canvases and
notebooks that need Typst content inline rather than a paginated document
- Vector PDF export from any successful compilation snapshot
- Live recompilation while the source changes (debounced, flicker-free)
- Embedded default fonts (Libertinus, New Computer Modern Math, DejaVu Sans
Mono) plus an API to register custom font bytes
- `@preview` Typst package support with on-demand downloads and local caching

## Platforms


| Platform    | Status               |
| ----------- | -------------------- |
| Linux       | Supported            |
| Android     | Supported            |
| Windows     | Supported            |
| iOS / macOS | Scaffolded, untested |
| Web         | Not supported yet    |


## Requirements

The Rust crate embedded in this package is built via
[cargokit](https://github.com/irondash/cargokit). On supported platforms,  
Cargokit automatically downloads and verifies a signed precompiled binary  
when Rust is **unavailable**. You need a Rust toolchain to build it locally or as  
a fallback when a matching precompiled binary is unavailable:

- A [Rust toolchain](https://rustup.rs) (`rustup`)
- For Android: NDK r26 or newer, plus the Rust targets for your ABIs, e.g.
`rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`

### Using precompiled binaries when you have Rust installed

Cargokit only reaches for the signed precompiled binaries automatically when
it can't find a Rust toolchain on your machine (i.e. no `rustup` on `PATH`).  
If you have Rust installed, Cargokit  
defaults to compiling this crate from source instead, even though a matching  
precompiled binary is published for your platform. That's a much slower build  
(the crate pulls in the Typst compiler and its dependencies).

To opt into using the precompiled binaries anyway, add a
`cargokit_options.yaml` file next to
your `pubspec.yaml`

```yaml
use_precompiled_binaries: true
```



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
final pdf = await result.document!.exportPdf(); // vector PDF bytes, tagged
final untaggedPdf = await result.document!.exportPdf(tagged: false); // for embedding
```

## Embedding content with `TypstPageView`

For canvases, notebooks, or any surface where Typst content sits inline
among other widgets rather than as a paginated document, compile as an
embedded fragment and render it with `TypstPageView` — no pan/zoom, sized
to its own content:

```dart
const width = 300.0; // Typst points — must match the scale below
await session.compileFragment(
  '#text(fill: blue)[Hello, fragment!]',
  const TypstFragmentOptions(width: width, transparent: true),
);

TypstPageView(
  session: session,
  scale: 1.0, // logical pixels per Typst point; keep in sync with `width`
  onSizeChanged: (size) => print('content is now $size'),
)
```

`TypstFragmentOptions` wraps your source in a generated `#set page(...)`
preamble (fixed width, height following content, transparent by default);
diagnostics, completions, and hover all report positions in *your* source,
not the wrapped one. `TypstPageView` only ever shows `pages.first`, so it
expects a session compiled with `compileFragment`/`updateFragmentSource`
rather than a multi-page `compile()`/`updateSource()` document.

Reading the current text selection (from either widget) works the same
way regardless of embedding:

```dart
TypstViewerParams(
  onSelectionChanged: (selection) => print(selection?.text),
)
// or, via a controller:
final text = controller.selection?.text;
```

## Roadmap

- Text search widget (the text model already supports `allMatches`-style search)
- Scroll thumbs, facing-page layouts, selection magnifier
- `SelectionArea` integration
- True sub-region rendering backend (typst-svg + resvg) for very high zoom
- Web support

## License

Apache-2.0. The Typst compiler is likewise Apache-2.0 licensed.
`third_party/typst-render-clip` vendors a modified copy of Typst's
`typst-render` crate (also Apache-2.0); see its
[`NOTICE.md`](third_party/typst-render-clip/NOTICE.md) for the change list,
as required by section 4(b) of the license. `typstrx` is not affiliated with
or endorsed by the Typst project.