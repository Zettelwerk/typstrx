import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../document/typst_link.dart';

/// Which modifier key makes mouse-wheel scroll zoom a [TypstViewer] instead
/// of panning it. See [TypstViewerParams.wheelZoomTrigger].
enum WheelZoomTrigger {
  /// Wheel scroll zooms while Control is held; otherwise it pans. The
  /// default — matches most viewers, editors, and browsers.
  control,

  /// Wheel scroll zooms while Shift is held; otherwise it pans.
  shift,

  /// Wheel scroll zooms while Alt is held; otherwise it pans.
  alt,

  /// Wheel scroll always zooms; it never pans.
  always,

  /// Wheel scroll never zooms; it always pans.
  never,
}

/// Configuration for [TypstViewer].
///
/// All fields have defaults, so `TypstViewerParams()` is a valid starting
/// point; override only what you need to change. The params are grouped
/// below by concern: layout & zoom, rasterization quality/performance,
/// appearance, text selection, links, and mouse-wheel behavior.
class TypstViewerParams {
  const TypstViewerParams({
    this.margin = 8.0,
    this.minScale = 0.25,
    this.maxScale = 8.0,
    this.maxRenderDpi = 288.0,
    this.previewDpi = 144.0,
    this.fixedRasterDpi,
    this.maxImageCacheBytes = 100 * 1024 * 1024,
    this.renderDelay = const Duration(milliseconds: 80),
    this.backgroundColor = const Color(0xffdddddd),
    this.pageDropShadow = const BoxShadow(
      color: Color(0x40000000),
      blurRadius: 4,
      offset: Offset(1, 2),
    ),
    this.enableTextSelection = true,
    this.selectionColor = const Color(0x553b82f6),
    this.onLinkTap,
    this.wheelZoomTrigger = WheelZoomTrigger.control,
    this.shouldZoomOnWheelScroll,
  });

  // ---- layout & zoom ----

  /// Space around the outside of the document and between consecutive
  /// pages, in Typst points (1pt = 1/72in; at zoom 1.0 this equals logical
  /// pixels).
  ///
  /// Applied on all four sides of each page and stacked vertically between
  /// pages — e.g. with the default `8.0`, there are 16pt between the bottom
  /// of one page and the top of the next (8pt trailing margin + 8pt leading
  /// margin).
  ///
  /// Defaults to `8.0`.
  final double margin;

  /// The lowest zoom the user can reach by pinching, scrolling, or calling
  /// [TypstViewerController.setZoom]. `1.0` means one Typst point per
  /// logical pixel; `0.5` shows the document at half size.
  ///
  /// The viewer's initial "fit width" zoom is also clamped to this bound,
  /// so a very narrow viewport won't zoom out further than this to fit the
  /// page.
  ///
  /// Defaults to `0.25` (25%).
  final double minScale;

  /// The highest zoom the user can reach by pinching, scrolling, or calling
  /// [TypstViewerController.setZoom].
  ///
  /// This bounds the *view* zoom, which is independent of
  /// [maxRenderDpi] — you can allow zooming in further than the
  /// rasterization sharpens (the image is then upscaled/blurry) by raising
  /// this without raising [maxRenderDpi], which trades sharpness for
  /// render cost.
  ///
  /// Defaults to `8.0` (800%).
  final double maxScale;

  // ---- rasterization quality & performance ----
  //
  // The viewer renders two tiers of raster image per page, in two stages:
  //
  // Stage one: a whole-page "preview" is always rasterized at the fixed
  // [previewDpi] baseline, regardless of current zoom — this exists so
  // every nearby page is at least legible the instant it's needed, without
  // waiting to find out what resolution the current zoom will end up
  // wanting. This matches pdfrx's preview tier (a fixed
  // `onePassRenderingScaleThreshold` target).
  //
  // Stage two: if the *current* zoom needs more resolution than that fixed
  // baseline provides, a sharper "tile" covering just the visible window is
  // rasterized on top, adaptively — `min(currentZoom * devicePixelRatio *
  // 72, maxRenderDpi)` DPI, capped by [maxRenderDpi]. Below that point (zoomed
  // out, or zoomed in but still under the preview's baseline), the fixed
  // preview alone is sharp enough and no tile is rendered at all.
  //
  // See TypstViewerController.currentRasterScale (and its DPI counterpart)
  // to read back which tier — and exact resolution — is actually on screen
  // right now.

  /// Upper bound, in DPI (dots/pixels per inch; 1 Typst point = 1/72in, so
  /// this is `pixelsPerPoint * 72`), for the high-resolution tile rendered
  /// for the page(s) under the viewport once the current zoom needs more
  /// resolution than the fixed [previewDpi] baseline provides (stage two —
  /// see the section intro above).
  ///
  /// The tile is rendered at `min(currentZoom * devicePixelRatio * 72,
  /// maxRenderDpi)` DPI, so this is the ceiling on how sharp the visible
  /// window ever gets, regardless of how far past it the user zooms (see
  /// [maxScale]). `72` DPI would mean one rendered pixel per Typst point at
  /// "100%" print scale — roughly screen resolution on a non-retina
  /// display; the default `288` is sharp on typical high-DPI displays.
  ///
  /// pdfrx's analogous high-res tile tier has no DPI ceiling of its own —
  /// it scales with zoom unbounded, relying only on the zoom range itself
  /// (its `maxScale`) to keep things sane. Set this very high (or raise
  /// [maxScale] and this together) to reproduce that "stays sharp at
  /// extreme zoom" behavior instead of capping out at a fixed ceiling.
  ///
  /// Raising this makes zoomed-in text/vector art sharper at the cost of
  /// render time and memory: both scale roughly with the *square* of this
  /// value (pixel count of the tile), and the Rust backend additionally
  /// rejects renders whose full-page pixel budget would be exceeded (see
  /// the `RenderTooLarge` error), so pushing this very high on large pages
  /// can start failing renders rather than just being slow. Values beyond
  /// ~350–450 DPI rarely produce a visible improvement.
  ///
  /// Defaults to `288.0` DPI. This was chosen from profiling a
  /// viewport-sized (900×700px) tile against a text-heavy A4 page on
  /// desktop (`cargo test --test render_bench -- --ignored --nocapture` in
  /// `rust/`, release profile): render time stays under ~12ms through 288
  /// DPI and only starts climbing steeply past ~360 DPI (22ms) as the
  /// page's *full* raster — not just the cropped tile — grows, since the
  /// v1 rasterizer renders the whole page and crops (see
  /// `rust/src/render.rs`). 288 DPI also comfortably exceeds what's useful
  /// for on-screen reading at typical device pixel ratios and zoom levels,
  /// so it sits at the point of diminishing quality returns just before
  /// the cost curve bends upward. The example app's rasterization panel
  /// (sliders + live render-time/size readout) is a good way to re-check
  /// this tradeoff against your own content and target devices.
  final double maxRenderDpi;

  /// The fixed DPI every page near the viewport is rasterized at up front
  /// (stage one — see the section intro above), regardless of current zoom.
  ///
  /// Unlike [maxRenderDpi] this is not a ceiling that adapts down when
  /// zoomed out: the preview always targets exactly this DPI, so every
  /// nearby page is at least this sharp the instant it's needed, without
  /// waiting to find out what resolution the current zoom will end up
  /// wanting. It's replaced by a sharper, zoom-adaptive tile (capped by
  /// [maxRenderDpi]) once the current zoom actually needs more than this
  /// provides; below that point, this fixed preview is what's on screen.
  /// This matches pdfrx's preview tier (a fixed
  /// `onePassRenderingScaleThreshold` target, independent of zoom).
  ///
  /// Because it's fixed rather than adaptive, and paid for *every* page
  /// near the viewport (not just the current one), this should generally
  /// stay well below [maxRenderDpi] — a high value here is wasted whenever
  /// a page is visible at a lower zoom than this DPI implies, and that
  /// waste multiplies across every nearby page, not just the one you're
  /// looking at.
  ///
  /// Defaults to `144.0` DPI. Profiling a full text-heavy A4 page (see
  /// [maxRenderDpi] for the benchmark command) shows this costs ~25ms —
  /// cheap enough to pay for several nearby pages sequentially during
  /// scroll without becoming perceptible, while already sharp enough that
  /// the difference versus the eventual hi-res tile is only visible in the
  /// brief moment before that tile finishes rendering (or not at all, if
  /// the current zoom never exceeds what this DPI already provides).
  final double previewDpi;

  /// Overrides both [previewDpi] and [maxRenderDpi] with a single value:
  /// when set, every render — preview *and* tile — targets exactly this
  /// DPI, always, no matter the current zoom or device pixel ratio. This
  /// disables stage two entirely: since preview and tile would target the
  /// same value, the sharper tile never has anything to add, so it never
  /// renders — there's only one raster per page, ever.
  ///
  /// The default (`null`) keeps stage two working normally: [previewDpi]
  /// rasterizes every nearby page at a fixed baseline up front, and once
  /// the current zoom needs more than that, a sharper tile (capped by
  /// [maxRenderDpi]) takes over for the visible page. That tile genuinely
  /// re-rasterizes from the compiled document at the new resolution — it's
  /// not scaling up a smaller bitmap — so it stays sharp all the way up to
  /// [maxRenderDpi] (see [TypstViewerController.currentRasterDpi] to read
  /// back which of the two is actually on screen at any moment).
  ///
  /// Setting [fixedRasterDpi] removes that safety net: the single raster is
  /// scaled on screen like any bitmap as you zoom past its native
  /// resolution — sharp near that DPI, increasingly blurry further past it,
  /// and wastefully oversampled zoomed out far below it. There's no
  /// adaptive tile to take over, by construction.
  ///
  /// This exists for comparing the two models hands-on (the example app's
  /// rasterization panel has a toggle for it) — e.g. against pdfrx, whose
  /// preview tier works exactly this way (a fixed
  /// `onePassRenderingScaleThreshold` target, defaulting to ~200 DPI, with
  /// no adaptive fallback of its own) while its separate high-res tile tier
  /// does not (it re-rasterizes at the actual zoom level, uncapped, which
  /// is what actually keeps text sharp at extreme pdfrx zoom levels — not
  /// the fixed preview DPI). Defaults to `null`.
  final double? fixedRasterDpi;

  /// Total memory budget, in bytes, for all cached page preview and tile
  /// images together.
  ///
  /// Each cached image costs `width * height * 4` bytes (RGBA8888). When
  /// the budget is exceeded, cached images for pages are evicted — farthest
  /// from [TypstViewerController.currentPageNumber] first — until back
  /// under budget; images for pages currently intersecting the viewport are
  /// never evicted regardless of budget.
  ///
  /// Defaults to `100 * 1024 * 1024` (100 MiB).
  final int maxImageCacheBytes;

  /// How long the viewer waits, after the last scroll/zoom change, before
  /// (re-)rendering page images for the new viewport.
  ///
  /// This debounces rendering during continuous interaction (a mouse-wheel
  /// scroll burst, a drag, a pinch) so intermediate viewport states don't
  /// each trigger a render call — only the settled end state does. Lower
  /// values make new tiles appear sooner after interaction stops, at the
  /// cost of more (wasted) render calls if the user is still actively
  /// scrolling; higher values reduce render churn but leave a visibly
  /// blurrier (stretched preview) view for longer after interaction stops.
  ///
  /// Defaults to `Duration(milliseconds: 80)`.
  final Duration renderDelay;

  // ---- appearance ----

  /// Color painted for the area around and between pages (i.e., everywhere
  /// that isn't a page itself).
  ///
  /// Defaults to a light gray, `Color(0xffdddddd)`.
  final Color backgroundColor;

  /// Drop shadow painted behind every page, giving pages visual separation
  /// from [backgroundColor] and from each other. Pass `null` for no shadow.
  ///
  /// Defaults to a soft shadow: `BoxShadow(color: Color(0x40000000),
  /// blurRadius: 4, offset: Offset(1, 2))`.
  final BoxShadow? pageDropShadow;

  // ---- text selection ----

  /// Whether page text can be selected — via mouse drag, double-click
  /// (word), or long-press (word, with drag handles) — and copied (via the
  /// selection toolbar's copy button or Ctrl/Cmd+C).
  ///
  /// When `false`, the viewer does no text-geometry loading or hit-testing
  /// for selection at all (link tapping and navigation are unaffected).
  ///
  /// Defaults to `true`.
  final bool enableTextSelection;

  /// Fill color painted over selected text. Should generally be
  /// semi-transparent so the underlying glyphs remain legible.
  ///
  /// Defaults to a translucent blue, `Color(0x553b82f6)`.
  final Color selectionColor;

  // ---- links ----

  /// Called when a link region on a page is tapped, for both URL links
  /// (`#link("https://...")`) and internal links (`#link(<label>)`).
  ///
  /// Internal links additionally scroll the viewer to their destination
  /// automatically (via [TypstViewerController.goToDest]) *before* this
  /// callback runs — you don't need to handle navigation yourself. This
  /// callback is where you'd open URL links externally, e.g. with the
  /// `url_launcher` package:
  ///
  /// ```dart
  /// TypstViewerParams(
  ///   onLinkTap: (link) {
  ///     if (link.url != null) launchUrl(link.url!);
  ///   },
  /// )
  /// ```
  ///
  /// Defaults to `null` (URL taps do nothing but the built-in internal
  /// navigation still applies).
  final void Function(TypstLink link)? onLinkTap;

  // ---- mouse wheel ----

  /// Which modifier key toggles mouse-wheel scroll between panning
  /// (default) and zooming.
  ///
  /// Ignored when [shouldZoomOnWheelScroll] is provided. Touch/stylus
  /// pan and pinch-zoom gestures are unaffected by this setting — it only
  /// governs the mouse scroll wheel.
  ///
  /// Defaults to [WheelZoomTrigger.control] (hold Control to zoom; plain
  /// scroll pans), matching the convention used by most viewers, editors,
  /// and browsers.
  final WheelZoomTrigger wheelZoomTrigger;

  /// Escape hatch that overrides [wheelZoomTrigger] with custom logic:
  /// return `true` to zoom in response to a given wheel scroll event,
  /// `false` to pan.
  ///
  /// Use this for triggers [WheelZoomTrigger] can't express — e.g.
  /// requiring two modifiers at once, or branching on
  /// [PointerScrollEvent.device] to give a presentation remote's scroll
  /// wheel different behavior than a mouse's:
  ///
  /// ```dart
  /// TypstViewerParams(
  ///   shouldZoomOnWheelScroll: (event) =>
  ///       HardwareKeyboard.instance.isControlPressed &&
  ///       HardwareKeyboard.instance.isShiftPressed,
  /// )
  /// ```
  ///
  /// Defaults to `null` ([wheelZoomTrigger] applies).
  final bool Function(PointerScrollEvent event)? shouldZoomOnWheelScroll;
}
