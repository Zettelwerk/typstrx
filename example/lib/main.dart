import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:typstrx/typstrx.dart';

const _initialSource = '''
= Hello, *world*!

This document is compiled by the native Typst compiler and rendered
by typstrx.

\$ sum_(k=1)^n k = (n(n+1)) / 2 \$

#lorem(50)
''';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Typstrx.init();
  final session = await TypstSession.create();
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
  TypstCompileResult? _lastResult;
  ui.Image? _pageImage;

  @override
  void initState() {
    super.initState();
    widget.session.results.listen(_onResult);
    widget.session.updateSource(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageImage?.dispose();
    super.dispose();
  }

  Future<void> _onResult(TypstCompileResult result) async {
    final document = result.document;
    ui.Image? uiImage;
    if (document != null && document.pages.isNotEmpty) {
      final page = document.pages.first;
      // Phase 1: render the whole first page at 2x for a crisp preview.
      final image = await page.render(
        fullWidth: page.width * 2,
        fullHeight: page.height * 2,
      );
      if (image != null) {
        uiImage = await image.createImage();
      }
    }
    if (!mounted) {
      uiImage?.dispose();
      return;
    }
    setState(() {
      _lastResult = result;
      if (uiImage != null) {
        _pageImage?.dispose();
        _pageImage = uiImage;
      }
    });
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
                  child: ColoredBox(
                    color: Colors.grey.shade300,
                    child: Center(
                      child: _pageImage == null
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(16),
                              child: RawImage(
                                image: _pageImage,
                                fit: BoxFit.contain,
                              ),
                            ),
                    ),
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
