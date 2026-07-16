import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:typstrx/typstrx.dart';

const _initialSource = '''
= Hello, *world*!

This document is compiled by the native Typst compiler and rendered
by typstrx. Try selecting this text with the mouse, or follow
#link("https://typst.app")[this link to typst.app].

\$ sum_(k=1)^n k = (n(n+1)) / 2 \$

#lorem(50)

Jump to the #link(<second>)[second page].

// Typst Universe packages download on demand, e.g.:
// #import "@preview/cetz:0.4.2"

#pagebreak()

= Second page <second>

#lorem(80)
''';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Typstrx.init();
  // An app-specific cache directory keeps `@preview` package downloads
  // working on platforms without the standard Typst cache dir (Android).
  final cacheDir = await getApplicationCacheDirectory();
  final session = await TypstSession.create(
    options: TypstSessionOptions(
      packageCacheDir: '${cacheDir.path}/typst-packages',
    ),
  );
  runApp(ExampleApp(session: session));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.session});

  final TypstSession session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'typstrx example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: EditorPage(session: session),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.session});

  final TypstSession session;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _controller = TextEditingController(text: _initialSource);
  final _viewerController = TypstViewerController();
  TypstCompileResult? _lastResult;

  // Live-adjustable rasterization params, in DPI — see TypstViewerParams
  // docs for what these trade off. Defaults match TypstViewerParams' own
  // defaults; drag the sliders and watch the metrics panel to explore the
  // tradeoff.
  double _maxRenderDpi = const TypstViewerParams().maxRenderDpi;
  double _previewDpi = const TypstViewerParams().previewDpi;
  bool _useFixedDpi = false;
  double _fixedDpi = const TypstViewerParams().previewDpi;

  @override
  void initState() {
    super.initState();
    widget.session.results.listen(_onResult);
    widget.session.updateSource(_controller.text);
    // Repaint the status bar whenever the viewer's pan/zoom or rendered
    // resolution changes, so the DPI readout stays live.
    _viewerController.addListener(_onViewerChanged);
  }

  void _onViewerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _viewerController.removeListener(_onViewerChanged);
    _viewerController.dispose();
    super.dispose();
  }

  void _onResult(TypstCompileResult result) {
    if (mounted) setState(() => _lastResult = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _lastResult;
    final diagnostics = result?.diagnostics ?? const <TypstDiagnostic>[];
    return Scaffold(
      appBar: AppBar(title: const Text('typstrx example')),
      body: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Typst source',
                ),
                onChanged: widget.session.updateSource,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: TypstViewer(
                    session: widget.session,
                    controller: _viewerController,
                    params: TypstViewerParams(
                      maxRenderDpi: _maxRenderDpi,
                      previewDpi: _previewDpi,
                      fixedRasterDpi: _useFixedDpi ? _fixedDpi : null,
                    ),
                  ),
                ),
                _RasterizationPanel(
                  maxRenderDpi: _maxRenderDpi,
                  previewDpi: _previewDpi,
                  useFixedDpi: _useFixedDpi,
                  fixedDpi: _fixedDpi,
                  onMaxRenderDpiChanged: (value) =>
                      setState(() => _maxRenderDpi = value),
                  onPreviewDpiChanged: (value) =>
                      setState(() => _previewDpi = value),
                  onUseFixedDpiChanged: (value) =>
                      setState(() => _useFixedDpi = value),
                  onFixedDpiChanged: (value) =>
                      setState(() => _fixedDpi = value),
                  viewerController: _viewerController,
                ),
                if (diagnostics.isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: Colors.red.shade50,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Text(
                        diagnostics.map((e) => e.toString()).join('\n'),
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                if (result != null)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      'generation ${result.generation} · '
                      '${result.elapsed.inMilliseconds} ms compile',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sliders for the two rasterization DPI caps plus a live metrics readout,
/// for exploring the quality/speed/memory tradeoff hands-on. Not part of the
/// typstrx public API — just example scaffolding.
class _RasterizationPanel extends StatelessWidget {
  const _RasterizationPanel({
    required this.maxRenderDpi,
    required this.previewDpi,
    required this.useFixedDpi,
    required this.fixedDpi,
    required this.onMaxRenderDpiChanged,
    required this.onPreviewDpiChanged,
    required this.onUseFixedDpiChanged,
    required this.onFixedDpiChanged,
    required this.viewerController,
  });

  final double maxRenderDpi;
  final double previewDpi;
  final bool useFixedDpi;
  final double fixedDpi;
  final ValueChanged<double> onMaxRenderDpiChanged;
  final ValueChanged<double> onPreviewDpiChanged;
  final ValueChanged<bool> onUseFixedDpiChanged;
  final ValueChanged<double> onFixedDpiChanged;
  final TypstViewerController viewerController;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall;
    return Container(
      color: Colors.indigo.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch(value: useFixedDpi, onChanged: onUseFixedDpiChanged),
              const SizedBox(width: 4),
              Text(
                'Fixed DPI (ignore zoom, like pdfrx\'s preview tier)',
                style: labelStyle,
              ),
            ],
          ),
          if (useFixedDpi)
            _DpiSlider(
              label: 'Fixed DPI',
              value: fixedDpi,
              onChanged: onFixedDpiChanged,
            )
          else
            Row(
              children: [
                Expanded(
                  child: _DpiSlider(
                    label: 'Tile cap (maxRenderDpi)',
                    value: maxRenderDpi,
                    onChanged: onMaxRenderDpiChanged,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _DpiSlider(
                    label: 'Preview cap (previewDpi)',
                    value: previewDpi,
                    onChanged: onPreviewDpiChanged,
                  ),
                ),
              ],
            ),
          Text(_metricsLine(), style: labelStyle),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  String _metricsLine() {
    final render = viewerController.lastRender;
    final renderPart = render == null
        ? 'no render yet'
        : '${render.isTile ? 'tile' : 'preview'} '
            '${render.width}×${render.height}px '
            '(${(render.byteSize / 1024).toStringAsFixed(0)} KB) in '
            '${render.renderTime.inMilliseconds} ms';
    final cacheMb = viewerController.cacheBytes / (1024 * 1024);
    return 'on screen: ${viewerController.currentRasterDpi.round()} dpi · '
        'last render: $renderPart · '
        'cache: ${cacheMb.toStringAsFixed(1)} MB / '
        '${viewerController.cachedImageCount} images';
  }
}

class _DpiSlider extends StatelessWidget {
  const _DpiSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 190,
          child: Text(
            '$label: ${value.round()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 36.0,
            max: 576.0,
            divisions: 30,
            label: '${value.round()} dpi',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
