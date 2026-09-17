import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:typstrx/typstrx.dart';

import 'page_view_example.dart';
import 'viewer_example.dart';

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

enum _Example { viewer, pageView }

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, required this.session});

  final TypstSession session;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  ThemeMode _themeMode = ThemeMode.system;
  _Example _example = _Example.viewer;

  void _setThemeMode(ThemeMode mode) => setState(() => _themeMode = mode);

  void _switchExample() => setState(() {
    _example = switch (_example) {
      _Example.viewer => _Example.pageView,
      _Example.pageView => _Example.viewer,
    };
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'typstrx example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      home: switch (_example) {
        _Example.viewer => ViewerExamplePage(
          session: widget.session,
          themeMode: _themeMode,
          onThemeModeChanged: _setThemeMode,
          onSwitchExample: _switchExample,
        ),
        _Example.pageView => PageViewExamplePage(
          session: widget.session,
          themeMode: _themeMode,
          onThemeModeChanged: _setThemeMode,
          onSwitchExample: _switchExample,
        ),
      },
    );
  }
}
