import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../document/typst_link.dart';
import '../document/typst_text_selection.dart';

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
    this.maxRenderDpi = 576.0,
    this.previewDpi = 144.0,
    this.fixedRasterDpi,
    this.tileScaleFactor = 1.0,
    this.maxImageCacheBytes = 100 * 1024 * 1024,
    this.renderDelay = const Duration(milliseconds: 16),
    this.backgroundColor = const Color(0xffdddddd),
    this.pageColor = const Color(0xffffffff),
    this.pageDropShadow = const BoxShadow(
      color: Color(0x40000000),
      blurRadius: 4,
      offset: Offset(1, 2),
    ),
    this.enableTextSelection = true,
    this.selectionColor = const Color(0x553b82f6),
    this.showSelectionToolbar = true,
    this.onSelectionChanged,
    this.enableNavigation = true,
    this.rasterBackgroundColor = const Color(0xffffffff),
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
  // tileScaleFactor * 72, maxRenderDpi)` DPI, capped by [maxRenderDpi]. Below
  // that point (zoomed out, or zoomed in but still under the preview's
  // baseline), the fixed preview alone is sharp enough and no tile is rendered
  // at all.
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
  /// The tile is rendered at `min(currentZoom * devicePixelRatio *
  /// tileScaleFactor * 72, maxRenderDpi)` DPI (see [tileScaleFactor], which
  /// defaults to `1.0`), so this is the ceiling on how sharp the visible
  /// window ever gets, regardless of how far past it the user zooms (see
  /// [maxScale]). `72` DPI would mean one rendered pixel per Typst point at
  /// "100%" print scale — roughly screen resolution on a non-retina
  /// display; the default `576` is sharp well past what high-DPI displays
  /// resolve, so text stays crisp deep into the zoom range.
  ///
  /// This is now a *quality* choice rather than a scaling limit. Tiles are
  /// rasterized directly into a tile-sized buffer (see `rust/src/render.rs`),
  /// so a tile costs what its own pixels cost — roughly constant, because the
  /// tile is viewport-sized no matter the zoom — instead of growing with the
  /// square of the zoom the way it did when the backend rasterized the whole
  /// page and cropped. Measured on a text-heavy A4 page
  /// (`cargo test --release --test tile_waste_bench -- --ignored --nocapture`
  /// in `rust/`), a viewport tile costs ~3ms flat from 144 through 500 DPI.
  /// Raising this therefore buys sharpness at very little cost; it is capped
  /// only so a pathological zoom cannot ask for an unbounded buffer (the
  /// backend rejects a tile past its pixel budget with `RenderTooLarge`).
  ///
  /// pdfrx's analogous high-res tile tier has no DPI ceiling of its own — it
  /// scales with zoom unbounded, relying only on the zoom range itself (its
  /// `maxScale`). Raise this and [maxScale] together to match that.
  ///
  /// The adaptive DPI snaps up to discrete rungs rather than tracking zoom
  /// continuously, so a range of zoom levels reuses one cached tile instead of
  /// re-rendering on every gesture frame; a tile is therefore never softer
  /// than the zoom asks for, and at most one rung sharper.
  ///
  /// Defaults to `576.0` DPI. The example app's rasterization panel (sliders
  /// + live render-time/size readout) is a good way to check the tradeoff
  /// against your own content and target devices.
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
  /// It also opts out of what makes stage two cheap, by construction. A tile
  /// costs roughly what the viewport costs because it is only ever rendered at
  /// viewport size; setting this makes every render a *whole page* at this DPI,
  /// for every page near the viewport, so cost climbs with the square of the
  /// value and the image cache fills far faster. High values here are
  /// correspondingly expensive in a way that [maxRenderDpi] no longer is.
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

  /// Multiplier applied to `currentZoom * devicePixelRatio` before it's
  /// converted to DPI and clamped by [maxRenderDpi], in stage two's tile
  /// scale calculation (see the section intro above): the tile targets
  /// `min(currentZoom * devicePixelRatio * tileScaleFactor * 72,
  /// maxRenderDpi)` DPI instead of the `1.0`-factor default.
  ///
  /// Raising it renders the tile sharper than the current zoom strictly
  /// requires (useful for prefetching ahead of a zoom-in gesture, or
  /// compensating for a display that under-reports its device pixel ratio);
  /// lowering it renders a softer tile than the zoom would otherwise get,
  /// trading sharpness for render time and memory. Ignored when
  /// [fixedRasterDpi] is set, since stage two never runs in that mode.
  ///
  /// Defaults to `1.0` (no adjustment — the tile matches the zoom exactly,
  /// up to the [maxRenderDpi] ceiling). The example app's rasterization
  /// panel has a slider for this.
  final double tileScaleFactor;

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
  /// Defaults to `Duration(milliseconds: 16)` — about one frame. The delay
  /// used to be an order of magnitude longer, back when a discarded render
  /// meant tens of milliseconds of wasted whole-page rasterization; a tile now
  /// costs a few milliseconds regardless of zoom, so waiting to find out
  /// whether the gesture has settled costs more latency than it saves work.
  /// pdfrx, whose renders are cancellable, waits `0` on native for the same
  /// reason.
  final Duration renderDelay;

  // ---- appearance ----

  /// Color painted for the area around and between pages (i.e., everywhere
  /// that isn't a page itself).
  ///
  /// Defaults to a light gray, `Color(0xffdddddd)`.
  final Color backgroundColor;

  /// Color painted behind each page raster. Pass `null` for an embedded,
  /// transparent surface (the compiled page fill still paints normally).
  final Color? pageColor;

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

  /// Whether typstrx builds its own Copy toolbar for rendered selections.
  /// Disable this when the host coordinates selection UI across surfaces.
  final bool showSelectionToolbar;

  /// Called whenever the rendered-text selection changes or is cleared.
  final ValueChanged<TypstTextSelection?>? onSelectionChanged;

  /// Whether this viewer owns pan, pinch-zoom, and mouse-wheel navigation.
  /// Text-selection gestures remain enabled independently.
  final bool enableNavigation;

  /// Color below the compiled page. Alpha is preserved by the renderer.
  final Color rasterBackgroundColor;

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
