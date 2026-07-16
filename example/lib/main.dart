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

  @override
  void initState() {
    super.initState();
    widget.session.results.listen(_onResult);
    widget.session.updateSource(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
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
                  ),
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
                      '${result.elapsed.inMilliseconds} ms',
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
