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

/// A large, layout-heavy document (headings, TOC, math, tables, lists across
/// ~40 pages) generated with Typst's own `#for` loop — good for exercising
/// pagination and rasterization performance with the [TypstViewer]'s
/// rasterization panel sliders.
const _stressTestSource = '''
#set page(numbering: "1")
#set heading(numbering: "1.1")

#align(center)[
  #text(24pt, weight: "bold")[Stress Test Document]

  #text(14pt)[Generated to exercise pagination and rasterization]
]

#outline()

#pagebreak()

#for i in range(1, 41) [
  = Section #i

  #lorem(120)

  == Section #i, subsection A

  A closed form for the sum of the first #i squares:

  \$ sum_(k=1)^#i k^2 = (#i (#i+1)(2 dot #i+1))/6 \$

  #lorem(60)

  == Section #i, subsection B

  #table(
    columns: 4,
    [*Row*], [*A*], [*B*], [*A+B*],
    ..range(1, 6).map(j => (
      [#j], [#(i * j)], [#(i + j)], [#(i * j + i + j)],
    )).flatten()
  )

  + First point for section #i
  + Second point for section #i
  + Third point for section #i, with some #emph[emphasis] and #strong[strength]

  #pagebreak()
]
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
  double _tileScaleFactor = const TypstViewerParams().tileScaleFactor;

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

  void _recompile() {
    widget.session.compile(_controller.text);
  }

  void _loadStressTest() {
    _controller.text = _stressTestSource;
    // Routed through updateSource rather than compile: assigning to
    // _controller.text does not fire the TextField's onChanged, so a debounce
    // armed by typing just before the click would still be holding the old
    // text and would compile it right back over the stress test. updateSource
    // cancels that pending timer. Compiling immediately as well would work but
    // costs a second compile, and every compile bumps the document generation,
    // which invalidates every cached page image.
    widget.session.updateSource(_stressTestSource);
  }

  @override
  Widget build(BuildContext context) {
    final result = _lastResult;
    final diagnostics = result?.diagnostics ?? const <TypstDiagnostic>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('typstrx example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_mosaic),
            tooltip: 'Load stress test document (~40 pages)',
            onPressed: _loadStressTest,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recompile now',
            onPressed: _recompile,
          ),
          const SizedBox(width: 24),
        ],
      ),
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
                      tileScaleFactor: _tileScaleFactor,
                    ),
                  ),
                ),
                _RasterizationPanel(
                  maxRenderDpi: _maxRenderDpi,
                  previewDpi: _previewDpi,
                  useFixedDpi: _useFixedDpi,
                  fixedDpi: _fixedDpi,
                  tileScaleFactor: _tileScaleFactor,
                  onMaxRenderDpiChanged: (value) =>
                      setState(() => _maxRenderDpi = value),
                  onPreviewDpiChanged: (value) =>
                      setState(() => _previewDpi = value),
                  onUseFixedDpiChanged: (value) =>
                      setState(() => _useFixedDpi = value),
                  onFixedDpiChanged: (value) =>
                      setState(() => _fixedDpi = value),
                  onTileScaleFactorChanged: (value) =>
                      setState(() => _tileScaleFactor = value),
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
    required this.tileScaleFactor,
    required this.onMaxRenderDpiChanged,
    required this.onPreviewDpiChanged,
    required this.onUseFixedDpiChanged,
    required this.onFixedDpiChanged,
    required this.onTileScaleFactorChanged,
    required this.viewerController,
  });

  final double maxRenderDpi;
  final double previewDpi;
  final bool useFixedDpi;
  final double fixedDpi;
  final double tileScaleFactor;
  final ValueChanged<double> onMaxRenderDpiChanged;
  final ValueChanged<double> onPreviewDpiChanged;
  final ValueChanged<bool> onUseFixedDpiChanged;
  final ValueChanged<double> onFixedDpiChanged;
  final ValueChanged<double> onTileScaleFactorChanged;
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
          if (!useFixedDpi)
            Row(
              children: [
                SizedBox(
                  width: 190,
                  child: Text(
                    'Tile scale factor: ${tileScaleFactor.toStringAsFixed(2)}',
                    style: labelStyle,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: tileScaleFactor,
                    min: 0.25,
                    max: 3.0,
                    divisions: 55,
                    label: tileScaleFactor.toStringAsFixed(2),
                    onChanged: onTileScaleFactorChanged,
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
