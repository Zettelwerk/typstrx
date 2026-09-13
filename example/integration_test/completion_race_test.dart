import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typstrx/typstrx.dart';

/// Real desktop, real-native-FFI confirmation that typing normally now
/// shows completion suggestions.
///
/// This used to fail: TypstCodeEditor's implicit trigger checked
/// `lastCompiledSource == controller.text` as soon as completions()
/// resolved (sub-10ms per completion_bench.rs), while the edit that
/// dispatched the request had also just restarted the host's own
/// page-render compile debounce (250ms by default) — so the edit that
/// triggered a request was always the same edit that invalidated its own
/// freshness check. Fixed by having the request ensure the World's source
/// matches before trusting a result, decoupled from whatever debounce (if
/// any) a host app drives page rendering with.
///
/// Run on a real window (not flutter test's fake binding) via:
///   flutter test integration_test/completion_race_test.dart -d linux
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await Typstrx.init());

  testWidgets(
    'typing #lo shows a completion popup with a real typing rhythm, no pre-compile',
    (tester) async {
      final session = await TypstSession.create(
        options: const TypstSessionOptions(allowPackageDownload: false),
      );
      final controller = TypstEditorController(session: session, text: '');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: TypstCodeEditor(
                controller: controller,
                onChanged: session.updateSource,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Real typing rhythm: one character at a time with real (not
      // fake-clock) delays between keystrokes — comfortably slower than a
      // human, so this can't be blamed on typing faster than a 250ms
      // debounce could ever catch up between keystrokes. Deliberately no
      // session.compile() call beforehand: that's exactly what a real host
      // app typing into a fresh editor looks like.
      for (final ch in '#lo'.split('')) {
        controller.value = TextEditingValue(
          text: controller.text + ch,
          selection: TextSelection.collapsed(
            offset: controller.text.length + 1,
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump();
      }

      expect(find.text('lorem'), findsOneWidget);

      // Real pause so an external screenshot can confirm this visually too.
      await Future<void>.delayed(const Duration(seconds: 8));
      await tester.pump();

      controller.dispose();
      await session.dispose();
    },
  );
}
