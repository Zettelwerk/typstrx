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
  // Deliberately not covering text entry through tester.enterText here: it
  // hangs partway through the call against this widget, inside
  // flutter_test's own showKeyboard/idle plumbing (reproduced in isolation;
  // a plain TextEditingController in the same EditableText/gesture-detector
  // shape doesn't hang there either — this is unrelated to
  // TypstEditorController). Not worth chasing further given text-entry
  // correctness is already covered at the seam EditableText actually calls
  // (TypstEditorController.set value, in typst_editor_controller_test.dart).
  // The tap test below covers what those unit tests can't: that focus,
  // hit-testing, and TextSelectionGestureDetectorBuilder wiring all work
  // against the real widget.
  //
  // Note for future tests in this file: don't await a raw
  // Future.delayed(...) inside a testWidgets body the way
  // typst_editor_controller_test.dart's plain test() bodies do — testWidgets
  // runs in flutter_test's FakeAsync zone, where a bare delayed Future never
  // resolves without a tester.pump() to advance the fake clock (this hung a
  // once-tracked-down-to-the-widget "bug" here that turned out to be
  // exactly this). Use tester.pump(duration) instead.
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
