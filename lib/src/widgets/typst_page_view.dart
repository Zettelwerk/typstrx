import 'dart:async';
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
  }) : assert(scale > 0);

  /// Logical pixels per Typst point.
  final double scale;
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
  TypstDocument? _document;
  Size? _lastReportedSize;

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
    _document = widget.session.document;
    _subscription = widget.session.documents.listen((document) {
      if (!mounted) return;
      setState(() => _document = document);
      _reportSize(document);
    });
    final document = _document;
    if (document != null) _reportSize(document);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document == null || document.pages.isEmpty) {
      return const SizedBox.shrink();
    }
    final page = document.pages.first;
    return SizedBox(
      width: page.width * widget.scale,
      height: page.height * widget.scale,
      child: TypstViewer(
        session: widget.session,
        controller: widget.controller,
        params: TypstViewerParams(
          margin: 0,
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
