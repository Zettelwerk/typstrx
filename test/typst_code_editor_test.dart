import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  /// What the next `completions()` call returns.
  List<rust.TypstCompletion> completionsToReturn = const [];
  int applyFromUtf16ToReturn = 0;

  /// When set, `completions()` blocks until this completes — for tests that
  /// need to mutate state while a request is deliberately kept in flight.
  Completer<void>? completionsGate;

  /// What the next `hover()` call returns.
  rust.TypstTooltip? tooltipToReturn;

  /// When set, `hover()` blocks until this completes — same purpose as
  /// [completionsGate], for hover's own staleness test.
  Completer<void>? hoverGate;

  @override
  Future<rust.HighlightNode> highlight({required String source}) async {
    return rust.HighlightNode(tag: null, text: source, children: const []);
  }

  @override
  Future<rust.CompletionResult> completions({required int cursorUtf16, required bool explicit}) async {
    if (completionsGate != null) await completionsGate!.future;
    return rust.CompletionResult(
      generation: BigInt.zero,
      applyFromUtf16: applyFromUtf16ToReturn,
      completions: completionsToReturn,
    );
  }

  @override
  Future<rust.HoverResult> hover({required int cursorUtf16}) async {
    if (hoverGate != null) await hoverGate!.future;
    return rust.HoverResult(generation: BigInt.zero, tooltip: tooltipToReturn);
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

  group('completion popup', () {
    // Compiles [text] (so TypstSession.lastCompiledSource matches it —
    // required for a completions result to be considered fresh, see
    // TypstCodeEditor's _requestCompletions), mounts the editor, then
    // assigns [text]/[cursor] to the controller to dispatch the triggering
    // request and pumps once for its (synchronous, ungated-by-default) fake
    // response to land.
    // [focusNode], when given, is focused *before* the triggering edit
    // below (via requestFocus, not a tap) — a tap lands wherever the finger
    // hits, which for an expanded editor and a couple of characters of text
    // is well past the end of the line, moving the selection there. Since
    // TypstCodeEditor treats any selection change with no text change as
    // "the buffer moved on, hide whatever was offered", a tap issued after
    // the popup is already showing dismisses it before a subsequent key
    // event reaches it.
    Future<(FakeRustSession, TypstSession, TypstEditorController)> triggerCompletions(
      WidgetTester tester, {
      required String text,
      required int cursor,
      List<rust.TypstCompletion> completions = const [],
      int applyFromUtf16 = 1,
      FocusNode? focusNode,
    }) async {
      final fake = FakeRustSession()
        ..completionsToReturn = completions
        ..applyFromUtf16ToReturn = applyFromUtf16;
      final session = TypstSession.forTesting(fake, const TypstSessionOptions());
      await session.compile(text);
      final controller = TypstEditorController(session: session, text: '');

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TypstCodeEditor(controller: controller, focusNode: focusNode))),
      );
      await tester.pump();

      if (focusNode != null) {
        focusNode.requestFocus();
        await tester.pump();
      }

      controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: cursor));
      await tester.pump(const Duration(milliseconds: 1));
      return (fake, session, controller);
    }

    const lorem = rust.TypstCompletion(kind: rust.TypstCompletionKind.func(), label: 'lorem', apply: 'lorem(\${})');
    const letBinding = rust.TypstCompletion(
      kind: rust.TypstCompletionKind.syntax(),
      label: 'let binding',
      apply: 'let',
    );

    testWidgets('a trigger shows a popup filtered to completions matching the typed prefix', (tester) async {
      final (_, session, controller) = await triggerCompletions(
        tester,
        text: '#lo',
        cursor: 3,
        completions: const [lorem, letBinding],
      );

      expect(find.text('lorem'), findsOneWidget);
      expect(find.text('let binding'), findsNothing, reason: "'let' does not start with the typed 'lo'");

      controller.dispose();
      await session.dispose();
    });

    testWidgets('arrow keys move the popup selection, not the text caret', (tester) async {
      const alpha = rust.TypstCompletion(kind: rust.TypstCompletionKind.func(), label: 'alpha', apply: 'alpha');
      const beta = rust.TypstCompletion(kind: rust.TypstCompletionKind.func(), label: 'beta', apply: 'beta');
      final focusNode = FocusNode();
      final (_, session, controller) = await triggerCompletions(
        tester,
        text: '#l',
        cursor: 2,
        completions: const [alpha, beta],
        applyFromUtf16: 2,
        focusNode: focusNode,
      );
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      final caretBefore = controller.selection.baseOffset;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.selection.baseOffset, caretBefore, reason: 'arrow-down navigates the popup, not the caret');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // applyFromUtf16 (2) equals the cursor (2): an empty replace range, so
      // 'beta' is inserted right there rather than replacing anything.
      expect(controller.text, '#lbeta', reason: 'arrow-down moved the popup selection to the second item');

      focusNode.dispose();
      controller.dispose();
      await session.dispose();
    });

    testWidgets('escape dismisses the popup', (tester) async {
      final focusNode = FocusNode();
      final (_, session, controller) = await triggerCompletions(
        tester,
        text: '#l',
        cursor: 2,
        completions: const [lorem],
        focusNode: focusNode,
      );
      expect(find.text('lorem'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text('lorem'), findsNothing);

      focusNode.dispose();
      controller.dispose();
      await session.dispose();
    });

    testWidgets('enter applies the completion with its snippet stripped and the caret at the placeholder', (
      tester,
    ) async {
      final focusNode = FocusNode();
      final (_, session, controller) = await triggerCompletions(
        tester,
        text: '#l',
        cursor: 2,
        completions: const [lorem],
        focusNode: focusNode,
      );
      expect(find.text('lorem'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // applyFromUtf16 (1, right after '#') to the cursor (2) is replaced by
      // 'lorem(${})' with its placeholder stripped: 'lorem()', caret
      // between the parens.
      expect(controller.text, '#lorem()');
      expect(controller.selection, const TextSelection.collapsed(offset: 7));

      focusNode.dispose();
      controller.dispose();
      await session.dispose();
    });

    testWidgets('a completion result that arrives after the buffer moved on is not shown', (tester) async {
      final fake = FakeRustSession()
        ..completionsToReturn = const [lorem]
        ..applyFromUtf16ToReturn = 1
        ..completionsGate = Completer<void>();
      final session = TypstSession.forTesting(fake, const TypstSessionOptions());
      await session.compile('#l');
      final controller = TypstEditorController(session: session, text: '');

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TypstCodeEditor(controller: controller))));
      await tester.pump();

      controller.value = const TextEditingValue(text: '#l', selection: TextSelection.collapsed(offset: 2));
      await tester.pump(const Duration(milliseconds: 1));

      // The buffer moves on (represented here by the native side's own
      // registered source changing, exactly the case
      // TypstSession.lastCompiledSource exists to detect) while the
      // completions() call above is still gated/in flight.
      await session.compile('#x');

      fake.completionsGate!.complete();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('lorem'), findsNothing, reason: 'stale result must not be shown');

      controller.dispose();
      await session.dispose();
    });
  });

  group('hover tooltip', () {
    // Moves a real (non-touch) pointer to [target] without ever pressing a
    // button, so MouseTracker treats it as a hover rather than a drag —
    // MouseRegion.onHover only fires for the former.
    Future<void> hoverTo(WidgetTester tester, Offset target) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(target);
    }

    testWidgets('hovering over the source shows the tooltip content', (tester) async {
      final fake = FakeRustSession()..tooltipToReturn = const rust.TypstTooltip.text(content: 'a heading');
      final session = TypstSession.forTesting(fake, const TypstSessionOptions());
      await session.compile('= Heading');
      final controller = TypstEditorController(session: session, text: '= Heading');

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TypstCodeEditor(controller: controller))));
      await tester.pump();

      // A few pixels into the editor's top-left corner, where the first
      // line of text renders — see _onHover's vertical-bounds check for
      // why a point that isn't actually on a line (e.g. the center of an
      // expands:true editor much taller than one line) must not trigger a
      // request in the first place.
      await hoverTo(tester, tester.getTopLeft(find.byType(TypstCodeEditor)) + const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('a heading'), findsOneWidget);

      controller.dispose();
      await session.dispose();
    });

    testWidgets('a hover result that arrives after the buffer moved on is not shown', (tester) async {
      final fake = FakeRustSession()
        ..tooltipToReturn = const rust.TypstTooltip.text(content: 'a heading')
        ..hoverGate = Completer<void>();
      final session = TypstSession.forTesting(fake, const TypstSessionOptions());
      await session.compile('= Heading');
      final controller = TypstEditorController(session: session, text: '= Heading');

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TypstCodeEditor(controller: controller))));
      await tester.pump();

      await hoverTo(tester, tester.getTopLeft(find.byType(TypstCodeEditor)) + const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 350));

      // The buffer moves on (represented here by the native side's own
      // registered source changing) while the hover() call above is still
      // gated/in flight.
      await session.compile('= Other');

      fake.hoverGate!.complete();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('a heading'), findsNothing, reason: 'stale hover result must not be shown');

      controller.dispose();
      await session.dispose();
    });
  });
}
