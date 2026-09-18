import 'dart:async';

import 'package:flutter/material.dart';
import 'package:typstrx/typstrx.dart';

const _initialSource = '''
= Embedded TypstPageView

This is a content-sized Typst fragment rendered inside a Flutter widget.
Edit it to exercise compile and rasterization timing.

\$ sum_(k=1)^n k = (n(n+1)) / 2 \$

#lorem(70)
''';

const _stressTestSource = '''
= Embedded stress test
#for i in range(1, 18) [
  == Section #i
  #lorem(80)
  #table(columns: 3, [*Item*], [*Value*], [*Note*], ..range(1, 5).map(n => ([#n], [#(i*n)], [Rasterize me])).flatten())
]
''';

/// Embedded example: a content-sized [TypstPageView] fragment dropped into a
/// normal scrolling layout, alongside a debug panel and its own editor pane.
class PageViewExamplePage extends StatefulWidget {
  const PageViewExamplePage({
    super.key,
    required this.session,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onSwitchExample,
  });
  final TypstSession session;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onSwitchExample;
  @override
  State<PageViewExamplePage> createState() => _PageViewExamplePageState();
}

class _PageViewExamplePageState extends State<PageViewExamplePage> {
  late final _editor = TypstEditorController(
    session: widget.session,
    text: _initialSource,
    analysisFragmentOptions: () =>
        TypstFragmentOptions(width: _fragmentWidth, transparent: _transparent),
  );
  final _pageView = TypstViewerController();
  Timer? _compileDebounce;
  TypstCompileResult? _result;
  Size? _pageSize;
  double _fragmentWidth = 360,
      _scale = .8,
      _pageMargin = 0,
      _previewDpi = 144,
      _maxRenderDpi = 576,
      _cacheMegabytes = 32;
  bool _transparent = true,
      _enableTextSelection = true,
      _showSelectionToolbar = false;

  @override
  void initState() {
    super.initState();
    widget.session.results.listen((result) {
      if (mounted) setState(() => _result = result);
    });
    _pageView.addListener(_repaintMetrics);
    _compileFragment();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    _editor.theme = TypstSyntaxTheme.forBrightness(brightness);
    _editor.errorColor = brightness == Brightness.dark
        ? TypstEditorController.darkErrorColor
        : TypstEditorController.defaultErrorColor;
    _editor.warningColor = brightness == Brightness.dark
        ? TypstEditorController.darkWarningColor
        : TypstEditorController.defaultWarningColor;
  }

  @override
  void dispose() {
    _compileDebounce?.cancel();
    _editor.dispose();
    _pageView.removeListener(_repaintMetrics);
    _pageView.dispose();
    super.dispose();
  }

  void _repaintMetrics() {
    if (mounted) setState(() {});
  }

  void _onSourceChanged(String _) {
    _compileDebounce?.cancel();
    _compileDebounce = Timer(
      const Duration(milliseconds: 250),
      _compileFragment,
    );
  }

  Future<void> _compileFragment() async {
    _compileDebounce?.cancel();
    await widget.session.compileFragment(
      _editor.text,
      TypstFragmentOptions(width: _fragmentWidth, transparent: _transparent),
    );
  }

  void _setAndCompile(VoidCallback update) {
    setState(update);
    _compileFragment();
  }

  IconData get _themeIcon => switch (widget.themeMode) {
    ThemeMode.system => Icons.brightness_auto,
    ThemeMode.light => Icons.light_mode,
    ThemeMode.dark => Icons.dark_mode,
  };
  void _cycleTheme() => widget.onThemeModeChanged(switch (widget.themeMode) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  });

  @override
  Widget build(BuildContext context) {
    final controls = _DebugPanel(
      fragmentWidth: _fragmentWidth,
      scale: _scale,
      pageMargin: _pageMargin,
      previewDpi: _previewDpi,
      maxRenderDpi: _maxRenderDpi,
      cacheMegabytes: _cacheMegabytes,
      transparent: _transparent,
      enableTextSelection: _enableTextSelection,
      showSelectionToolbar: _showSelectionToolbar,
      pageSize: _pageSize,
      result: _result,
      diagnostics: _result?.diagnostics ?? const [],
      controller: _pageView,
      onFragmentWidthChanged: (v) => _setAndCompile(() => _fragmentWidth = v),
      onScaleChanged: (v) => setState(() => _scale = v),
      onPageMarginChanged: (v) => setState(() => _pageMargin = v),
      onPreviewDpiChanged: (v) => setState(() => _previewDpi = v),
      onMaxRenderDpiChanged: (v) => setState(() => _maxRenderDpi = v),
      onCacheMegabytesChanged: (v) => setState(() => _cacheMegabytes = v),
      onTransparentChanged: (v) => _setAndCompile(() => _transparent = v),
      onEnableTextSelectionChanged: (v) =>
          setState(() => _enableTextSelection = v),
      onShowSelectionToolbarChanged: (v) =>
          setState(() => _showSelectionToolbar = v),
      onRecompile: _compileFragment,
    );
    final embedded = _EmbeddedPane(
      child: TypstPageView(
        session: widget.session,
        controller: _pageView,
        scale: _scale,
        pageMargin: _pageMargin,
        previewDpi: _previewDpi,
        maxRenderDpi: _maxRenderDpi,
        maxImageCacheBytes: (_cacheMegabytes * 1024 * 1024).round(),
        enableTextSelection: _enableTextSelection,
        showSelectionToolbar: _showSelectionToolbar,
        onSizeChanged: (size) => setState(() => _pageSize = size),
      ),
    );
    final editor = _EditorPane(editor: _editor, onChanged: _onSourceChanged);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TypstPageView embedded test'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Switch example',
            onPressed: widget.onSwitchExample,
          ),
          IconButton(
            icon: Icon(_themeIcon),
            tooltip: 'Toggle theme',
            onPressed: _cycleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_mosaic),
            tooltip: 'Load stress-test source',
            onPressed: () {
              _editor.text = _stressTestSource;
              _compileFragment();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Compile now',
            onPressed: _compileFragment,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(
              children: [
                Expanded(child: embedded),
                controls,
                Expanded(child: editor),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: embedded),
                    controls,
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: editor),
            ],
          );
        },
      ),
    );
  }
}

class _EmbeddedPane extends StatelessWidget {
  const _EmbeddedPane({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              const Icon(Icons.widgets_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                'Embedded TypstPageView',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              primary: true,
              padding: const EdgeInsets.all(24),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Typst's default foreground is black. The fragment can
                    // stay transparent while this host canvas guarantees
                    // readable text in the app's dark theme.
                    color: Colors.white,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 8),
                    ],
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _EditorPane extends StatelessWidget {
  const _EditorPane({required this.editor, required this.onChanged});
  final TypstEditorController editor;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Typst fragment source',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.all(8),
            child: TypstCodeEditor(
              controller: editor,
              onChanged: onChanged,
              detailsBuilder: defaultTypstDetailsBuilder,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ],
    ),
  );
}

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({
    required this.fragmentWidth,
    required this.scale,
    required this.pageMargin,
    required this.previewDpi,
    required this.maxRenderDpi,
    required this.cacheMegabytes,
    required this.transparent,
    required this.enableTextSelection,
    required this.showSelectionToolbar,
    required this.pageSize,
    required this.result,
    required this.diagnostics,
    required this.controller,
    required this.onFragmentWidthChanged,
    required this.onScaleChanged,
    required this.onPageMarginChanged,
    required this.onPreviewDpiChanged,
    required this.onMaxRenderDpiChanged,
    required this.onCacheMegabytesChanged,
    required this.onTransparentChanged,
    required this.onEnableTextSelectionChanged,
    required this.onShowSelectionToolbarChanged,
    required this.onRecompile,
  });
  final double fragmentWidth,
      scale,
      pageMargin,
      previewDpi,
      maxRenderDpi,
      cacheMegabytes;
  final bool transparent, enableTextSelection, showSelectionToolbar;
  final Size? pageSize;
  final TypstCompileResult? result;
  final List<TypstDiagnostic> diagnostics;
  final TypstViewerController controller;
  final ValueChanged<double> onFragmentWidthChanged,
      onScaleChanged,
      onPageMarginChanged,
      onPreviewDpiChanged,
      onMaxRenderDpiChanged,
      onCacheMegabytesChanged;
  final ValueChanged<bool> onTransparentChanged,
      onEnableTextSelectionChanged,
      onShowSelectionToolbarChanged;
  final VoidCallback onRecompile;
  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    final render = controller.lastRender;
    final compileText = result == null
        ? 'Compile: waiting'
        : 'Compile: ${result!.success ? 'success' : 'failed'} · generation ${result!.generation} · ${result!.elapsed.inMilliseconds} ms';
    final rasterText = render == null
        ? 'Raster: waiting for first render'
        : 'Raster: ${render.isTile ? 'tile' : 'preview'} ${render.width}×${render.height}px · ${(render.byteSize / 1024).toStringAsFixed(0)} KB · ${render.renderTime.inMilliseconds} ms';
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TypstPageView debug controls',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onRecompile,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Compile'),
              ),
            ],
          ),
          _DebugSlider(
            label: 'Fragment width',
            value: fragmentWidth,
            min: 180,
            max: 640,
            divisions: 23,
            suffix: 'pt',
            onChanged: onFragmentWidthChanged,
          ),
          _DebugSlider(
            label: 'Widget scale',
            value: scale,
            min: .25,
            max: 1.5,
            divisions: 25,
            suffix: '×',
            onChanged: onScaleChanged,
          ),
          _DebugSlider(
            label: 'Page margin',
            value: pageMargin,
            min: 0,
            max: 96,
            divisions: 32,
            suffix: 'pt',
            onChanged: onPageMarginChanged,
          ),
          _DebugSlider(
            label: 'Preview DPI',
            value: previewDpi,
            min: 36,
            max: 576,
            divisions: 30,
            suffix: 'dpi',
            onChanged: onPreviewDpiChanged,
          ),
          _DebugSlider(
            label: 'Max render DPI',
            value: maxRenderDpi,
            min: 36,
            max: 576,
            divisions: 30,
            suffix: 'dpi',
            onChanged: onMaxRenderDpiChanged,
          ),
          _DebugSlider(
            label: 'Image cache limit',
            value: cacheMegabytes,
            min: 1,
            max: 128,
            divisions: 127,
            suffix: 'MB',
            onChanged: onCacheMegabytesChanged,
          ),
          Wrap(
            spacing: 12,
            children: [
              _DebugSwitch(
                label: 'Transparent fragment',
                value: transparent,
                onChanged: onTransparentChanged,
              ),
              _DebugSwitch(
                label: 'Enable text selection',
                value: enableTextSelection,
                onChanged: onEnableTextSelectionChanged,
              ),
              _DebugSwitch(
                label: 'Selection toolbar',
                value: showSelectionToolbar,
                onChanged: onShowSelectionToolbarChanged,
              ),
            ],
          ),
          Text(compileText, style: textStyle),
          Text(rasterText, style: textStyle),
          Text(
            'Page: ${pageSize == null ? 'waiting' : '${pageSize!.width.toStringAsFixed(0)} × ${pageSize!.height.toStringAsFixed(0)} pt'} · actual raster ${controller.currentRasterDpi.round()} dpi · cache ${(controller.cacheBytes / 1048576).toStringAsFixed(1)} MB / ${controller.cachedImageCount} images',
            style: textStyle,
          ),
          if (diagnostics.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(6),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text(
                diagnostics.map((d) => d.toString()).join('\n'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DebugSlider extends StatelessWidget {
  const _DebugSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });
  final String label, suffix;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 138,
        child: Text(
          '$label: ${suffix == '×' ? value.toStringAsFixed(2) : value.round()} $suffix',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

class _DebugSwitch extends StatelessWidget {
  const _DebugSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(value: value, onChanged: onChanged),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
