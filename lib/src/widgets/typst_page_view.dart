import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';

import '../document/typst_document.dart';
import '../document/typst_link.dart';
import '../document/typst_session.dart';
import '../document/typst_text_selection.dart';
import 'typst_viewer.dart';
import 'typst_viewer_params.dart';

/// A host-controlled, single-page Typst surface for canvases and notebooks.
///
/// The widget follows [session]'s latest document, displays only its first
/// page, and sizes itself to that page at [scale]. It never pans or zooms;
/// those gestures belong to the surrounding host. Compile the session with
/// [TypstSession.compileFragment] to get content-sized transparent output.
class TypstPageView extends StatefulWidget {
  const TypstPageView({
    super.key,
    required this.session,
    this.scale = 1,
    this.pageMargin = 0,
    this.controller,
    this.enableTextSelection = true,
    this.selectionColor = const Color(0x553b82f6),
    this.showSelectionToolbar = false,
    this.onSelectionChanged,
    this.onSizeChanged,
    this.onLinkTap,
    this.previewDpi = 144,
    this.maxRenderDpi = 576,
    this.maxImageCacheBytes = 32 * 1024 * 1024,
  }) : assert(scale > 0),
       assert(pageMargin >= 0);

  /// Logical pixels per Typst point.
  final double scale;

  /// Transparent space around the embedded page, in Typst points.
  ///
  /// This controls viewer layout only. Use [TypstFragmentOptions.margin] to
  /// add margin inside the compiled Typst page itself.
  final double pageMargin;

  final TypstSession session;
  final TypstViewerController? controller;
  final bool enableTextSelection;
  final Color selectionColor;
  final bool showSelectionToolbar;
  final ValueChanged<TypstTextSelection?>? onSelectionChanged;

  /// Called when the first compiled page's unscaled size changes.
  final ValueChanged<Size>? onSizeChanged;
  final void Function(TypstLink link)? onLinkTap;
  final double previewDpi;
  final double maxRenderDpi;
  final int maxImageCacheBytes;

  @override
  State<TypstPageView> createState() => _TypstPageViewState();
}

class _TypstPageViewState extends State<TypstPageView> {
  StreamSubscription<TypstDocument>? _subscription;
  // Only this staged document is allowed to affect the widget's SizedBox.
  // The session may already hold a newer document while its first preview is
  // being generated, but that must not resize an old raster underneath us.
  TypstDocument? _document;
  Size? _lastReportedSize;
  int _stageRequest = 0;
  ui.Image? _stagedPreview;
  double? _stagedPreviewScale;
  Duration _stagedPreviewRenderTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(TypstPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) _attach();
  }

  void _attach() {
    _subscription?.cancel();
    _document = null;
    _subscription = widget.session.documents.listen(_stageDocument);
    final document = widget.session.document;
    if (document != null) _stageDocument(document);
  }

  /// Pre-renders the next page before allowing it to change this widget's
  /// size. This avoids one frame where a prior-generation image is stretched
  /// to the freshly compiled fragment's new height.
  Future<void> _stageDocument(TypstDocument document) async {
    if (document.pages.isEmpty) return;
    final request = ++_stageRequest;
    final page = document.pages.first;
    final scale = widget.previewDpi / 72.0;
    final stopwatch = Stopwatch()..start();
    final raster = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
      backgroundColor: const Color(0x00000000),
    );
    if (!mounted || request != _stageRequest || raster == null) return;

    // Decode too: this makes the hand-off wait for the complete Dart-side
    // raster pipeline, not merely for Rust to return raw pixels.
    final image = await raster.createImage();
    stopwatch.stop();
    if (!mounted || request != _stageRequest) {
      image.dispose();
      return;
    }
    setState(() {
      _document = document;
      _stagedPreview = image;
      _stagedPreviewScale = scale;
      _stagedPreviewRenderTime = stopwatch.elapsed;
    });
    _reportSize(document);
    // The newly keyed viewer consumes the image during this frame. Clear our
    // reference afterwards; its image cache owns disposal from that point.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _document != document) return;
      setState(() => _stagedPreview = null);
    });
  }

  void _reportSize(TypstDocument document) {
    if (document.pages.isEmpty) return;
    final page = document.pages.first;
    final size = Size(page.width, page.height);
    if (size == _lastReportedSize) return;
    _lastReportedSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSizeChanged?.call(size);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stageRequest++;
    // A preview that has not yet been handed to a viewer is ours to dispose.
    _stagedPreview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document == null || document.pages.isEmpty) {
      return const SizedBox.shrink();
    }
    final page = document.pages.first;
    final canvasWidth = page.width + widget.pageMargin * 2;
    final canvasHeight = page.height + widget.pageMargin * 2;
    return SizedBox(
      width: canvasWidth * widget.scale,
      height: canvasHeight * widget.scale,
      child: TypstViewer(
        // A new document may have different dimensions. Reusing the viewer
        // would let its previous-generation raster be laid out at those new
        // dimensions for one frame, visibly stretching it until the new
        // preview arrives. A generation key drops that stale raster instead.
        key: ValueKey(document.generation),
        session: widget.session,
        document: document,
        initialPreviewImage: _stagedPreview,
        initialPreviewScale: _stagedPreviewScale,
        initialPreviewRenderTime: _stagedPreviewRenderTime,
        controller: widget.controller,
        pageMargin: widget.pageMargin,
        params: TypstViewerParams(
          minScale: widget.scale,
          maxScale: widget.scale,
          previewDpi: widget.previewDpi,
          maxRenderDpi: widget.maxRenderDpi,
          maxImageCacheBytes: widget.maxImageCacheBytes,
          backgroundColor: const Color(0x00000000),
          pageColor: null,
          pageDropShadow: null,
          rasterBackgroundColor: const Color(0x00000000),
          enableNavigation: false,
          enableTextSelection: widget.enableTextSelection,
          selectionColor: widget.selectionColor,
          showSelectionToolbar: widget.showSelectionToolbar,
          onSelectionChanged: widget.onSelectionChanged,
          onLinkTap: widget.onLinkTap,
        ),
      ),
    );
  }
}
