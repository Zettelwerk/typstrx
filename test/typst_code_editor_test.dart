import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typstrx/src/document/typst_session.dart';
import 'package:typstrx/src/rust/api/session.dart' as rust;
import 'package:typstrx/src/rust/api/types.dart' as rust;
import 'package:typstrx/src/widgets/editor/typst_code_editor.dart';
import 'package:typstrx/src/widgets/editor/typst_editor_controller.dart';

/// A fake bridge session — same shape as the one in
/// typst_editor_controller_test.dart, needed here too since these tests
/// exercise a real, mounted [TypstEditorController].
class FakeRustSession implements rust.TypstSession {
  @override
  Future<rust.HighlightNode> highlight({required String source}) async {
    return rust.HighlightNode(tag: null, text: source, children: const []);
  }

  @override
  Future<rust.CompletionResult> completions({required int cursorUtf16, required bool explicit}) async {
    return rust.CompletionResult(generation: BigInt.zero, applyFromUtf16: 0, completions: const []);
  }

  @override
  Future<rust.HoverResult> hover({required int cursorUtf16}) async {
    return rust.HoverResult(generation: BigInt.zero, tooltip: null);
  }

  @override
  Future<rust.CompileResult> compile({required String source}) async {
    return rust.CompileResult(
      generation: BigInt.zero,
      success: true,
      pages: const [rust.PageInfo(widthPt: 595, heightPt: 842)],
      diagnostics: const [],
      elapsedMs: BigInt.zero,
    );
  }

  @override
  Future<rust.RenderedRegion> renderPageRegion({
    required BigInt generation,
    required int pageIndex,
    required int x,
    required int y,
    required int width,
    required int height,
    required int fullWidth,
    required int fullHeight,
    required int backgroundArgb,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<rust.PageTextData> pageText({required BigInt generation, required int pageIndex}) async {
    throw UnimplementedError();
  }

  @override
  Future<int> registerFont({required List<int> data}) async => 1;

  @override
  Future<void> setFile({required String path, required List<int> data}) async {}

  var _disposed = false;

  @override
  void dispose() => _disposed = true;

  @override
  bool get isDisposed => _disposed;
}

void main() {
  // Neither test below awaits a bare `Future<void>.delayed(...)` (unlike
  // typst_editor_controller_test.dart's plain test() bodies, where that's
  // fine). testWidgets runs inside flutter_test's FakeAsync zone, and a
  // delayed Future there never resolves without a tester.pump() to advance
  // the fake clock — awaiting one hangs the test indefinitely. That one
  // mistake, not any real widget or gesture-detector issue, is what an
  // earlier version of this file's commit chased for a while: it looked
  // exactly like a hang inside `enterText`/`tap` because a passing
  // `expect()` prints nothing, so "hung after the real work already
  // succeeded" and "hung during the real work" were indistinguishable from
  // the test output alone.
  testWidgets('typing text updates the controller and calls onChanged', (tester) async {
    final fake = FakeRustSession();
    final session = TypstSession.forTesting(fake, const TypstSessionOptions());
    final controller = TypstEditorController(session: session, text: 'hello');
    String? changed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypstCodeEditor(controller: controller, onChanged: (text) => changed = text),
        ),
      ),
    );
    await tester.pump();
    expect(controller.text, 'hello');

    await tester.enterText(find.byType(TypstCodeEditor), 'hello world');
    expect(controller.text, 'hello world');
    expect(changed, 'hello world');

    controller.dispose();
    await session.dispose();
  });

  testWidgets('tapping the editor requests focus (gesture wiring is live)', (tester) async {
    final fake = FakeRustSession();
    final session = TypstSession.forTesting(fake, const TypstSessionOptions());
    final controller = TypstEditorController(session: session, text: 'hello world');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypstCodeEditor(controller: controller, focusNode: focusNode),
        ),
      ),
    );
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);

    await tester.tap(find.byType(TypstCodeEditor));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    focusNode.dispose();
    controller.dispose();
    await session.dispose();
  });
}
