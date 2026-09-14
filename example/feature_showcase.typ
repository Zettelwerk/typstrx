// typstrx feature showcase
//
// Paste this into TypstEditorController / TypstSession.updateSource. It is
// deliberately self-contained: no network packages, files, or custom fonts
// are required. It therefore also makes a useful PDF-export smoke test.
//
// Host features exercised by this document:
// - live compilation and source diagnostics (uncomment the final line to test)
// - syntax highlighting, completions, hover information, and code folding
// - paged/viewport rendering, pan/zoom, text selection, and link navigation
// - structured text and link extraction, and vector-PDF export
//
// See the notes at the end for custom fonts, project files, and @preview
// package caching, which are configured through TypstSession rather than here.

#set document(title: "typstrx feature showcase", author: "typstrx")
#set page(margin: 18mm, numbering: "1 / 1")
#set heading(numbering: "1.")

#let badge(label, color) = box(
  inset: (x: 7pt, y: 3pt),
  radius: 3pt,
  fill: color.lighten(75%),
  stroke: color,
)[#text(fill: color, weight: "bold", size: 8pt)[#label]]

#align(center)[
  #text(size: 24pt, weight: "bold")[typstrx]
  \
  #text(size: 13pt)[A compact Typst rendering showcase]
]

This document is compiled by typstrx's native Typst engine. You can select
this sentence, zoom the page, and follow the #link("https://typst.app")[Typst
website] or jump to #link(<details>)[the second page].

#badge("live compilation", blue) #h(6pt)
#badge("selectable text", green) #h(6pt)
#badge("tappable links", purple)

= Document content

The same compilation snapshot supports high-resolution viewport rendering,
structured text/link geometry, and vector PDF export.

#table(
  columns: (1fr, 2fr),
  inset: 6pt,
  stroke: luma(190),
  table.header([*Typst element*], [*What it exercises*]),
  [Headings + outline], [Document structure and editor folding.],
  [Text + emphasis], [Selection and structured-text extraction.],
  [Links], [External and internal navigation.],
  [Math, tables, raw code], [Native compilation and rasterization.],
)

== Typesetting

- _Emphasis_, *strong text*, and inline `raw code`.
- A computed expression: #calc.pow(2, 10) is $2^10$.
- A displayed equation:

$ sum_(k=1)^n k = (n (n + 1)) / 2 $

```typst
#let greeting(name) = [Hello, #name!]
#greeting("typstrx")
```

#pagebreak()

= Interactive details <details>

== Links and navigation

Use #link(<features>)[this internal destination] to check link geometry and
navigation. The external link on page 1 exercises URL handling too.

#box(fill: luma(245), inset: 10pt, radius: 4pt)[
  *Tip:* Edit any text in the source editor to see debounced, flicker-free
  recompilation. The viewer preserves its document model while it refreshes.
]

== Session-provided features <features>

These capabilities are intentionally configured by Flutter/Dart, not embedded
in a `.typ` file:

- Register custom font bytes with `session.registerFont(...)`.
- Provide images or other project files with `session.setFile(...)`, then use
  `#image("/path/in/project.png")`.
- Import `@preview` packages; typstrx downloads and caches them on demand.
- Export the successful document as an accessible vector PDF with
  `document.exportPdf()`.

// Uncomment to showcase a source-location diagnostic in the editor:
// #this-is-not-a-valid-typst-function()
