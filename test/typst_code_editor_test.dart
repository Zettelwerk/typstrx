import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoTextSelectionToolbarButton;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typstrx/src/document/typst_session.dart';
import 'package:typstrx/src/rust/api/session.dart' as rust;
import 'package:typstrx/src/rust/api/types.dart' as rust;
import 'package:typstrx/src/widgets/editor/typst_code_editor.dart';
import 'package:typstrx/src/widgets/editor/typst_details_builder.dart';
import 'package:typstrx/src/widgets/editor/typst_editor_controller.dart';
import 'package:typstrx/src/widgets/editor/typst_editor_selection_controls.dart';
import 'package:typstrx/src/widgets/editor/typst_line_number_gutter.dart';

/// A fake bridge session — same shape as the one in
/// typst_editor_controller_test.dart, needed here too since these tests
/// exercise a real, mounted [TypstEditorController].
class FakeRustSession implements rust.TypstSession {
  final compiledSources = <String>[];

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

  /// What `functionInfo()` returns for a given `label`, when present in this
  /// map; falls back to [functionInfoToReturn] otherwise — lets a test give
  /// two different function completions two different, distinguishable
  /// results.
  final functionInfoByLabel = <String, rust.TypstFunctionInfo?>{};

  /// What `functionInfo()` returns when [functionInfoByLabel] has no entry
  /// for the requested label.
  rust.TypstFunctionInfo? functionInfoToReturn;

  /// When set, `functionInfo()` blocks until this completes — same purpose
  /// as [completionsGate]/[hoverGate], for its own staleness/dismiss tests.
  Completer<void>? functionInfoGate;

  /// Every `functionInfo()` call's `label` argument, in order — lets tests
  /// assert which item(s) were actually fetched.
  final functionInfoCalls = <String>[];

  @override
  Future<rust.FunctionInfoResult> functionInfo({
    required int cursorUtf16,
    required String label,
  }) async {
    functionInfoCalls.add(label);
    if (functionInfoGate != null) await functionInfoGate!.future;
    final info = functionInfoByLabel.containsKey(label)
        ? functionInfoByLabel[label]
        : functionInfoToReturn;
    return rust.FunctionInfoResult(generation: BigInt.zero, info: info);
  }

  @override
  Future<List<rust.TypstFoldingRange>> foldingRanges({
    required String source,
  }) async => const [];

  @override
  Future<rust.HighlightNode> highlight({required String source}) async {
    return rust.HighlightNode(tag: null, text: source, children: const []);
  }

  @override
  Future<rust.CompletionResult> completions({
    required int cursorUtf16,
    required bool explicit,
  }) async {
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
    compiledSources.add(source);
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
  Future<rust.PageTextData> pageText({
    required BigInt generation,
    required int pageIndex,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> exportPdf({
    required BigInt generation,
    required bool tagged,
  }) async {
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

/// Wraps [text] as a single-token signature — tests here only care about
/// the joined display text, not per-token coloring (that's exercised at the
/// Rust/`describe_func` level, not here).
List<rust.TypstSignatureToken> _sig(String text) {
  return [
    rust.TypstSignatureToken(
      text: text,
      kind: rust.TypstSignatureTokenKind.name,
    ),
  ];
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
  testWidgets('typing text updates the controller and calls onChanged', (
    tester,
  ) async {
    final fake = FakeRustSession();
    final session = TypstSession.forTesting(fake, const TypstSessionOptions());
    final controller = TypstEditorController(session: session, text: 'hello');
    String? changed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypstCodeEditor(
            controller: controller,
            onChanged: (text) => changed = text,
          ),
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

  testWidgets(
    'defaults to pdfrx-style triangle handles, one instance across rebuilds',
    (tester) async {
      final fake = FakeRustSession();
      final session = TypstSession.forTesting(
        fake,
        const TypstSessionOptions(),
      );
      final controller = TypstEditorController(session: session, text: 'hello');
      TextSelectionControls? controls() => tester
          .widget<EditableText>(find.byType(EditableText))
          .selectionControls;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypstCodeEditor(controller: controller)),
        ),
      );
      await tester.pump();
      final first = controls();
      expect(first, isA<TypstEditorSelectionControls>());

      // A fresh instance per build makes EditableText tear down and recreate
      // its whole selection overlay (see its didUpdateWidget) on every
      // rebuild of this widget — including mid-drag.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCodeEditor(
              controller: controller,
              cursorColor: const Color(0xFF123456),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controls(), same(first));

      controller.dispose();
      await session.dispose();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.linux,
    }),
  );

  // EditableText's own `showSelectionHandles` defaults to false — TextField
  // works it out per gesture and passes it down, and TypstCodeEditor (which
  // builds EditableText directly) has to do the same, or handles never show
  // at all on any platform.
  group('selection handles', () {
    final platforms = TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.linux,
    });

    Future<(TypstSession, TypstEditorController)> mountEditor(
      WidgetTester tester,
      String text,
    ) async {
      final fake = FakeRustSession();
      final session = TypstSession.forTesting(
        fake,
        const TypstSessionOptions(),
      );
      final controller = TypstEditorController(session: session, text: text);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypstCodeEditor(controller: controller)),
        ),
      );
      await tester.pump();
      return (session, controller);
    }

    bool handlesShown(WidgetTester tester) => tester
        .widget<EditableText>(find.byType(EditableText))
        .showSelectionHandles;

    Offset caretCenter(WidgetTester tester, int offset) {
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      return render.localToGlobal(
        render.getLocalRectForCaret(TextPosition(offset: offset)).center,
      );
    }

    final triangleFlags = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_TriangleHandlePainter',
    );

    testWidgets('a touch long-press shows both triangle handles', (
      tester,
    ) async {
      final (session, controller) = await mountEditor(tester, 'hello world');

      await tester.longPressAt(caretCenter(tester, 2));
      await tester.pumpAndSettle();

      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(handlesShown(tester), isTrue);
      // Rendered, not just requested: hidden handles stay in the overlay,
      // faded to zero opacity rather than removed.
      expect(triangleFlags, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final fade = tester.widget<FadeTransition>(
          find
              .ancestor(
                of: triangleFlags.at(i),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(fade.opacity.value, 1.0);
      }

      controller.dispose();
      await session.dispose();
    }, variant: platforms);

    testWidgets('a visible handle can be dragged by touch', (tester) async {
      final (session, controller) = await mountEditor(tester, 'hello world');
      await tester.longPressAt(caretCenter(tester, 2));
      await tester.pumpAndSettle();
      // Out of the way of the handle, whatever the platform puts where
      // (`false`: keep the handles themselves).
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .hideToolbar(false);
      await tester.pumpAndSettle();

      // The end handle's flag hangs down-right from the selection's bottom
      // right corner.
      final gesture = await tester.startGesture(
        caretCenter(tester, 5) + const Offset(6, 12),
      );
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(13, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 11),
      );

      controller.dispose();
      await session.dispose();
    }, variant: platforms);

    testWidgets(
      'the selection toolbar keeps clear of both handles',
      (tester) async {
        final text = List.generate(12, (i) => 'line$i words here').join('\n');
        final (session, controller) = await mountEditor(tester, text);
        final toolbarButtons = find.byWidgetPredicate(
          (w) =>
              w is TextSelectionToolbarTextButton ||
              w is CupertinoTextSelectionToolbarButton ||
              w is DesktopTextSelectionToolbarButton,
        );
        Rect rectOf(Finder finder) => List.generate(
          finder.evaluate().length,
          (i) => tester.getRect(finder.at(i)),
        ).reduce((a, b) => a.expandToInclude(b));

        // Line 0 has no room above it, so a mobile toolbar flips below the
        // selection there; line 10 does, so it stays above.
        for (final line in [0, 10]) {
          await tester.longPressAt(
            caretCenter(tester, text.indexOf('line$line ') + 8),
          );
          await tester.pumpAndSettle();
          expect(controller.selection.textInside(text), 'words');

          final toolbar = rectOf(toolbarButtons);
          expect(triangleFlags, findsNWidgets(2));
          for (var i = 0; i < 2; i++) {
            final flag = tester.getRect(triangleFlags.at(i));
            expect(
              toolbar.overlaps(flag),
              isFalse,
              reason: 'line $line: toolbar $toolbar covers handle $flag',
            );
          }

          tester
              .state<EditableTextState>(find.byType(EditableText))
              .hideToolbar();
          // iOS only selects a word on long-press while unfocused (focused, it
          // moves the caret instead).
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }

        controller.dispose();
        await session.dispose();
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.iOS,
      }),
    );

    testWidgets('a mouse drag-select keeps the handles hidden', (tester) async {
      final (session, controller) = await mountEditor(tester, 'hello world');

      final gesture = await tester.startGesture(
        caretCenter(tester, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(caretCenter(tester, 5));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.selection.isCollapsed, isFalse);
      expect(handlesShown(tester), isFalse);

      controller.dispose();
      await session.dispose();
    }, variant: platforms);

    testWidgets('a mouse right-click opens the menu without handles', (
      tester,
    ) async {
      final (session, controller) = await mountEditor(tester, 'hello world');

      final gesture = await tester.startGesture(
        caretCenter(tester, 2),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Toggle Comment'), findsOneWidget);
      expect(handlesShown(tester), isFalse);

      controller.dispose();
      await session.dispose();
    }, variant: platforms);

    testWidgets(
      'a hidden handle does not swallow a mouse click on the text under it',
      (tester) async {
        final (session, controller) = await mountEditor(
          tester,
          'aaaa\nbbbb\ncccc',
        );

        // Placing the caret also inserts the (hidden) handles into the overlay.
        await tester.tapAt(
          caretCenter(tester, 2),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(kDoubleTapTimeout);
        expect(controller.selection, const TextSelection.collapsed(offset: 2));

        // Straight below the caret: where the hidden collapsed handle sits.
        await tester.tapAt(
          caretCenter(tester, 7),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(kDoubleTapTimeout);
        expect(controller.selection, const TextSelection.collapsed(offset: 7));

        controller.dispose();
        await session.dispose();
      },
      variant: platforms,
    );
  });

  group('magnifier', () {
    // Drives typstEditorMagnifierConfiguration's builder directly rather
    // than through a real drag — EditableText only ever shows the
    // magnifier mid-gesture, which is awkward to hold open in a widget
    // test, and both geometry bugs these guard live entirely in this
    // builder, independent of how it gets shown. (Real handle-drag
    // MagnifierInfo values were confirmed separately, on a live Linux
    // build driving an actual handle drag — this builder can't be trusted
    // to invent them correctly on its own.)
    Future<void> pumpMagnifier(WidgetTester tester, MagnifierInfo info) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // Positioned (what the builder returns) needs a Stack ancestor
            // to interpret left/top — the real Overlay it normally sits in
            // provides one; this test supplies its own.
            body: Stack(
              children: [
                Builder(
                  builder: (context) =>
                      typstEditorMagnifierConfiguration.magnifierBuilder(
                        context,
                        MagnifierController(),
                        ValueNotifier(info),
                      ) ??
                      const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('centers its view exactly on the gesture position', (
      tester,
    ) async {
      const focal = Offset(300, 500);
      await pumpMagnifier(
        tester,
        const MagnifierInfo(
          globalGesturePosition: focal,
          caretRect: Rect.fromLTWH(295, 490, 2, 20),
          currentLineBoundaries: Rect.fromLTWH(0, 490, 600, 20),
          fieldBounds: Rect.fromLTWH(0, 0, 600, 800),
        ),
      );

      // Whatever's shown at the magnifier widget's own on-screen center
      // must be the true focal point: `center + focalPointOffset == focal`
      // — the RawMagnifier API's own contract (see its focalPointOffset
      // doc). Getting this wrong by even `magnifierSize.height / 2` shows
      // roughly the bottom half of the intended content instead of all of
      // it, centered.
      final magnifier = tester.widget<RawMagnifier>(find.byType(RawMagnifier));
      final magnifierCenter = tester.getRect(find.byType(RawMagnifier)).center;
      expect(
        magnifierCenter + magnifier.focalPointOffset,
        offsetMoreOrLessEquals(focal, epsilon: 0.5),
      );
    });

    testWidgets(
      'during a handle drag, locks vertically to the line rather than the '
      'gesture position',
      (tester) async {
        // A real finger dragging the end handle sits on its flag, which
        // hangs well below the line it points to (see
        // TypstEditorSelectionControls) — EditableText reports that as a
        // `globalGesturePosition` far from `currentLineBoundaries`, which
        // it derives independently from the drag's *resolved* text
        // position instead.
        const gesturePosition = Offset(300, 560);
        const line = Rect.fromLTWH(0, 490, 600, 20);
        await pumpMagnifier(
          tester,
          const MagnifierInfo(
            globalGesturePosition: gesturePosition,
            caretRect: Rect.fromLTWH(295, 490, 2, 20),
            currentLineBoundaries: line,
            fieldBounds: Rect.fromLTWH(0, 0, 600, 800),
          ),
        );

        final magnifier = tester.widget<RawMagnifier>(
          find.byType(RawMagnifier),
        );
        final magnifierCenter = tester
            .getRect(find.byType(RawMagnifier))
            .center;
        final shown = magnifierCenter + magnifier.focalPointOffset;
        expect(
          shown.dy,
          moreOrLessEquals(line.center.dy, epsilon: 0.5),
          reason:
              'should show the line the handle points to, not wherever on the handle the finger is',
        );
        expect(shown.dx, moreOrLessEquals(gesturePosition.dx, epsilon: 0.5));
      },
    );
  });

  group('long-press-and-drag granularity', () {
    // Flutter's own default snaps a long-press-drag to whole words on every
    // platform except iOS/macOS (TextSelectionGestureDetectorBuilder
    // .onSingleLongTapMoveUpdate) — the right choice for prose, but Typst
    // source is code: identifiers and punctuation don't split into words
    // the way prose does, and dragging a handle after releasing already
    // gives character precision. TypstEditorGestureDetectorBuilder makes
    // the initial drag (before release) match that.
    final platforms = TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.linux,
    });

    Offset caretCenter(WidgetTester tester, int offset) {
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      return render.localToGlobal(
        render.getLocalRectForCaret(TextPosition(offset: offset)).center,
      );
    }

    testWidgets('extends one character at a time, not by whole words', (
      tester,
    ) async {
      final fake = FakeRustSession();
      final session = TypstSession.forTesting(
        fake,
        const TypstSessionOptions(),
      );
      final controller = TypstEditorController(
        session: session,
        text: 'some words here to select carefully',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypstCodeEditor(controller: controller)),
        ),
      );
      await tester.pump();

      // Long-press "to" (offsets 16..18) — a standard word-grab start.
      final press = await tester.startGesture(
        caretCenter(tester, 17),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.selection.textInside(controller.text), 'to');

      // Drag 3 characters into "select" (19..25) — a whole-word snap would
      // land on "to select"; character precision stops mid-word instead.
      await press.moveTo(caretCenter(tester, 22));
      await tester.pump(const Duration(milliseconds: 20));
      expect(controller.selection.textInside(controller.text), 'to sel');

      await press.up();
      controller.dispose();
      await session.dispose();
    }, variant: platforms);

    testWidgets(
      'dragging back past the original word keeps a valid, shrinking selection',
      (tester) async {
        final fake = FakeRustSession();
        final session = TypstSession.forTesting(
          fake,
          const TypstSessionOptions(),
        );
        final controller = TypstEditorController(
          session: session,
          text: 'some words here to select carefully',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TypstCodeEditor(controller: controller)),
          ),
        );
        await tester.pump();

        final press = await tester.startGesture(
          caretCenter(tester, 17),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(const Duration(milliseconds: 600));
        // Establish the fixed edge by first dragging right...
        await press.moveTo(caretCenter(tester, 22));
        await tester.pump(const Duration(milliseconds: 20));
        // ...then drag left, back across the original word and past it.
        await press.moveTo(caretCenter(tester, 12));
        await tester.pump(const Duration(milliseconds: 20));
        expect(controller.selection.isCollapsed, isFalse);
        expect(controller.selection.textInside(controller.text), 'ere ');

        await press.up();
        controller.dispose();
        await session.dispose();
      },
      variant: platforms,
    );
  });

  testWidgets(
    'shows a line-number gutter by default, hidden via showLineNumbers: false',
    (tester) async {
      final fake = FakeRustSession();
      final session = TypstSession.forTesting(
        fake,
        const TypstSessionOptions(),
      );
      final controller = TypstEditorController(
        session: session,
        text: 'one\ntwo\nthree',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: TypstCodeEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byType(TypstLineNumberGutter), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: TypstCodeEditor(
                controller: controller,
                showLineNumbers: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TypstLineNumberGutter), findsNothing);

      controller.dispose();
      await session.dispose();
    },
  );

  testWidgets('updates line numbers on the first frame after a newline edit', (
    tester,
  ) async {
    final fake = FakeRustSession();
    final session = TypstSession.forTesting(fake, const TypstSessionOptions());
    final controller = TypstEditorController(session: session, text: 'one');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: TypstCodeEditor(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('2'), findsNothing);

    controller.value = const TextEditingValue(
      text: 'one\n',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pump();

    expect(find.text('2'), findsOneWidget);

    controller.dispose();
    await session.dispose();
  });

  testWidgets('tapping the editor requests focus (gesture wiring is live)', (
    tester,
  ) async {
    final fake = FakeRustSession();
    final session = TypstSession.forTesting(fake, const TypstSessionOptions());
    final controller = TypstEditorController(
      session: session,
      text: 'hello world',
    );
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
    Future<(FakeRustSession, TypstSession, TypstEditorController)>
    triggerCompletions(
      WidgetTester tester, {
      required String text,
      required int cursor,
      List<rust.TypstCompletion> completions = const [],
      int applyFromUtf16 = 1,
      FocusNode? focusNode,
      TypstDetailsBuilder? detailsBuilder,
      FakeRustSession? fake,
    }) async {
      final theFake = fake ?? FakeRustSession();
      theFake
        ..completionsToReturn = completions
        ..applyFromUtf16ToReturn = applyFromUtf16;
      final session = TypstSession.forTesting(
        theFake,
        const TypstSessionOptions(),
      );
      await session.compile(text);
      final controller = TypstEditorController(session: session, text: '');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCodeEditor(
              controller: controller,
              focusNode: focusNode,
              detailsBuilder: detailsBuilder,
            ),
          ),
        ),
      );
      await tester.pump();

      if (focusNode != null) {
        focusNode.requestFocus();
        await tester.pump();
      }

      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor),
      );
      // Past _completionDebounceDelay (150ms): the implicit trigger no
      // longer fires immediately, see typst_code_editor.dart's
      // _scheduleCompletions. session.compile(text) above already matches
      // what's assigned here, so the request's own "compile if stale"
      // step is a no-op — this is purely waiting out the debounce timer.
      await tester.pump(const Duration(milliseconds: 160));
      return (theFake, session, controller);
    }

    const lorem = rust.TypstCompletion(
      kind: rust.TypstCompletionKind.func(),
      label: 'lorem',
      apply: 'lorem(\${})',
    );
    const letBinding = rust.TypstCompletion(
      kind: rust.TypstCompletionKind.syntax(),
      label: 'let binding',
      apply: 'let',
    );

    testWidgets(
      'a trigger shows a popup filtered to completions matching the typed prefix',
      (tester) async {
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#lo',
          cursor: 3,
          completions: const [lorem, letBinding],
        );

        expect(find.text('lorem'), findsOneWidget);
        expect(
          find.text('let binding'),
          findsNothing,
          reason: "'let' does not start with the typed 'lo'",
        );

        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'an implicit trigger compiles first when the World has not caught up to this text',
      (tester) async {
        // Unlike the triggerCompletions helper (which pre-compiles to isolate
        // other behavior), this deliberately does NOT call session.compile()
        // before the edit — reproducing the actual reported bug: a host
        // app's own page-render compile is debounced and, in real typing,
        // essentially never catches up before a naive freshness check would
        // run. lastCompiledSource is null here at request time; the fix is
        // that _runCompletionsRequest compiles itself when it doesn't match.
        final fake = FakeRustSession()
          ..completionsToReturn = const [lorem]
          ..applyFromUtf16ToReturn = 1;
        final session = TypstSession.forTesting(
          fake,
          const TypstSessionOptions(),
        );
        final controller = TypstEditorController(session: session, text: '');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TypstCodeEditor(controller: controller)),
          ),
        );
        await tester.pump();
        expect(
          session.lastCompiledSource,
          isNull,
          reason: 'nothing has compiled yet — this is the point',
        );

        controller.value = const TextEditingValue(
          text: '#lo',
          selection: TextSelection.collapsed(offset: 3),
        );
        await tester.pump(const Duration(milliseconds: 160));

        expect(find.text('lorem'), findsOneWidget);
        expect(session.lastCompiledSource, '#lo');

        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'an implicit trigger preserves the configured fragment compile mode',
      (tester) async {
        final fake = FakeRustSession()
          ..completionsToReturn = const [lorem]
          ..applyFromUtf16ToReturn = 1;
        final session = TypstSession.forTesting(
          fake,
          const TypstSessionOptions(),
        );
        final controller = TypstEditorController(
          session: session,
          text: '',
          analysisFragmentOptions: () =>
              const TypstFragmentOptions(width: 321, margin: 7),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TypstCodeEditor(controller: controller)),
          ),
        );
        await tester.pump();
        controller.value = const TextEditingValue(
          text: '#lo',
          selection: TextSelection.collapsed(offset: 3),
        );
        await tester.pump(const Duration(milliseconds: 160));

        expect(fake.compiledSources, hasLength(1));
        expect(
          fake.compiledSources.single,
          startsWith(
            '#set page(width: 321pt, height: auto, margin: 7pt, fill: none)\n',
          ),
        );

        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets('a long detail string does not overflow the popup row', (
      tester,
    ) async {
      // The detail text in a completion row must be a bounded-width widget;
      // a bare Text(detail) isn't, and a long one-sentence description used
      // to trip the old ListTile-based row's own layout assertion (reported
      // against the real app via Ctrl+Space). Guards the same case for
      // whatever builder is wired up — currently defaultTypstCompletionsBuilder.
      const longDetail = rust.TypstCompletion(
        kind: rust.TypstCompletionKind.func(),
        label: 'lorem',
        apply: 'lorem(\${})',
        detail:
            'Generates a given amount of placeholder Lorem Ipsum text, for filling in layouts.',
      );
      final (_, session, controller) = await triggerCompletions(
        tester,
        text: '#lo',
        cursor: 3,
        completions: const [longDetail],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('lorem'), findsOneWidget);

      controller.dispose();
      await session.dispose();
    });

    testWidgets('the selected row shows its full detail; other rows do not', (
      tester,
    ) async {
      const alpha = rust.TypstCompletion(
        kind: rust.TypstCompletionKind.func(),
        label: 'alpha',
        apply: 'alpha',
        detail: 'Alpha description',
      );
      const beta = rust.TypstCompletion(
        kind: rust.TypstCompletionKind.func(),
        label: 'beta',
        apply: 'beta',
        detail: 'Beta description',
      );
      final focusNode = FocusNode();
      final (_, session, controller) = await triggerCompletions(
        tester,
        text: '#l',
        cursor: 2,
        completions: const [alpha, beta],
        applyFromUtf16: 2,
        focusNode: focusNode,
      );

      expect(
        find.text('Alpha description'),
        findsOneWidget,
        reason: 'alpha is selected by default (index 0)',
      );
      expect(find.text('Beta description'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(
        find.text('Alpha description'),
        findsNothing,
        reason: 'selection moved away from alpha',
      );
      expect(
        find.text('Beta description'),
        findsOneWidget,
        reason: 'selection moved to beta',
      );

      focusNode.dispose();
      controller.dispose();
      await session.dispose();
    });

    testWidgets(
      'the popup and details panel stay within a short window instead of being cropped',
      (tester) async {
        // A window this short can't fit the popup's own un-clamped preferred
        // height (200) below a caret sitting near the top of it — pre-fix,
        // Positioned(top: anchor.dy + 4) let it render past the window's
        // bottom edge, and the Overlay's own Stack hard-clipped whatever
        // didn't fit, cropping rows (and the details panel) rather than
        // scrolling them into a shorter, still fully visible popup.
        tester.view.physicalSize = const Size(500, 120);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final items = [
          for (var i = 0; i < 8; i++)
            rust.TypstCompletion(
              kind: rust.TypstCompletionKind.func(),
              label: 'item$i',
              apply: 'item$i',
              detail: 'a reasonably long description for item$i',
            ),
        ];
        final focusNode = FocusNode();
        final fake = FakeRustSession()
          ..functionInfoToReturn = rust.TypstFunctionInfo(
            name: 'item0',
            signature: _sig('item0(x)'),
          );
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#',
          cursor: 1,
          completions: items,
          focusNode: focusNode,
          fake: fake,
          detailsBuilder: (context, info) =>
              Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
        );
        await tester.pump(
          const Duration(milliseconds: 1),
        ); // let the details fetch land

        final windowBottom = 120.0;
        final popupRect = tester.getRect(find.byType(Scrollbar));
        expect(
          popupRect.bottom,
          lessThanOrEqualTo(windowBottom + 0.5),
          reason:
              'the completions list must fit (and scroll internally), not render past the window',
        );
        final detailsRect = tester.getRect(find.text('DETAILS:item0(x)'));
        expect(
          detailsRect.bottom,
          lessThanOrEqualTo(windowBottom + 0.5),
          reason: 'the details panel must also fit within the window',
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    // The details panel is often taller than the list beside it. Below the
    // caret, both hang from their top edges; above it, both must rest on
    // their bottom edges instead, or the shorter list floats away from the
    // line it's completing.
    Future<(Rect list, Rect details, Rect caret)> popupBesideTallDetails(
      WidgetTester tester, {
      required int line,
    }) async {
      final items = [
        for (var i = 0; i < 2; i++)
          rust.TypstCompletion(
            kind: rust.TypstCompletionKind.func(),
            label: 'item$i',
            apply: 'item$i',
            detail: 'item $i',
          ),
      ];
      final text = '${'\n' * line}#';
      final fake = FakeRustSession()
        ..completionsToReturn = items
        ..applyFromUtf16ToReturn = text.length
        ..functionInfoToReturn = rust.TypstFunctionInfo(
          name: 'item0',
          signature: _sig('item0(x)'),
        );
      final session = TypstSession.forTesting(
        fake,
        const TypstSessionOptions(),
      );
      await session.compile(text);
      // The lines are laid out before `#` is typed, as when typing for real.
      // (Swapping all of them in at once, like `triggerCompletions` does,
      // lands in the frame that first builds the popup, which then opened
      // as if the caret were still on line 0.)
      final controller = TypstEditorController(
        session: session,
        text: '\n' * line,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCodeEditor(
              controller: controller,
              detailsBuilder: (context, info) => const SizedBox(
                key: ValueKey('details'),
                width: 100,
                height: 300,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      await tester.pump(
        const Duration(milliseconds: 160),
      ); // completion debounce
      await tester.pump(
        const Duration(milliseconds: 1),
      ); // let the details fetch land

      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: text.length),
      );
      final rects = (
        tester.getRect(find.byType(Scrollbar)),
        tester.getRect(find.byKey(const ValueKey('details'))),
        Rect.fromPoints(
          render.localToGlobal(caret.topLeft),
          render.localToGlobal(caret.bottomRight),
        ),
      );
      controller.dispose();
      await session.dispose();
      return rects;
    }

    testWidgets(
      'opening below the caret, the list and a taller details panel align at the top',
      (tester) async {
        final (list, details, caret) = await popupBesideTallDetails(
          tester,
          line: 0,
        );

        expect(details.top, moreOrLessEquals(caret.bottom + 4, epsilon: 0.5));
        expect(list.top, moreOrLessEquals(details.top, epsilon: 0.5));
      },
    );

    testWidgets(
      'opening above the caret, the list and a taller details panel align at the bottom',
      (tester) async {
        final (list, details, caret) = await popupBesideTallDetails(
          tester,
          line: 38,
        );
        final where = 'list $list, details $details, caret $caret';

        expect(
          details.bottom,
          moreOrLessEquals(caret.top - 4, epsilon: 0.5),
          reason: where,
        );
        expect(
          list.bottom,
          moreOrLessEquals(details.bottom, epsilon: 0.5),
          reason: where,
        );
      },
    );

    testWidgets(
      'arrow-up from the first item wraps to the last, scrolling the whole (now-taller) row into view',
      (tester) async {
        // Each item carries a detail string so the wrapped-to row grows a
        // second (description) line once selected — a plain jumpTo(the
        // pre-selection maxScrollExtent estimate) lands short of that growth,
        // cropping the description even though the label is visible. See
        // _scrollSelectedIntoView's doc comment.
        final items = [
          for (var i = 0; i < 15; i++)
            rust.TypstCompletion(
              kind: rust.TypstCompletionKind.func(),
              label: 'item$i',
              apply: 'item$i',
              detail:
                  'This is a considerably long description string that should force multiple wrapped lines item$i',
            ),
        ];
        final focusNode = FocusNode();
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#',
          cursor: 1,
          completions: items,
          focusNode: focusNode,
        );

        final scrollbarRect = tester.getRect(find.byType(Scrollbar));
        expect(
          find.text('item14'),
          findsNothing,
          reason:
              'ListView.builder never built the last row — it starts well below the visible popup',
        );

        // _moveCompletionSelection wraps (0 - 1) around to the last index —
        // exactly the case a plain Scrollable.ensureVisible can't handle on
        // its own, since that row was never built to begin with (just shown
        // above) and so has no context to scroll to.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();

        expect(
          tester.getRect(find.text('item14')).bottom,
          lessThanOrEqualTo(scrollbarRect.bottom + 1.0),
          reason:
              'wrapping selection to the last item scrolled its label into view',
        );
        expect(
          tester
              .getRect(
                find.text(
                  'This is a considerably long description string that should force multiple wrapped lines item14',
                ),
              )
              .bottom,
          lessThanOrEqualTo(scrollbarRect.bottom + 1.0),
          reason:
              'the wrapped-to row grew a detail line once selected — that must be in view too, not just the label',
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'arrow-down from the last item wraps to the first, scrolling the whole (now-taller) row into view',
      (tester) async {
        final items = [
          for (var i = 0; i < 15; i++)
            rust.TypstCompletion(
              kind: rust.TypstCompletionKind.func(),
              label: 'item$i',
              apply: 'item$i',
              detail:
                  'This is a considerably long description string that should force multiple wrapped lines item$i',
            ),
        ];
        final focusNode = FocusNode();
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#',
          cursor: 1,
          completions: items,
          focusNode: focusNode,
        );

        // Get to the last item first (same mechanism as the up-wrap case),
        // then wrap forward off the end back to the first.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        final scrollbarRect = tester.getRect(find.byType(Scrollbar));
        expect(
          find.text('item0'),
          findsNothing,
          reason: 'scrolled to the bottom, item0 is no longer built',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        expect(
          tester.getRect(find.text('item0')).top,
          greaterThanOrEqualTo(scrollbarRect.top - 1.0),
        );
        expect(
          tester
              .getRect(
                find.text(
                  'This is a considerably long description string that should force multiple wrapped lines item0',
                ),
              )
              .bottom,
          lessThanOrEqualTo(scrollbarRect.bottom + 1.0),
          reason:
              'the wrapped-to row grew a detail line once selected — that must be in view too, not just the label',
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets('arrow keys move the popup selection, not the text caret', (
      tester,
    ) async {
      const alpha = rust.TypstCompletion(
        kind: rust.TypstCompletionKind.func(),
        label: 'alpha',
        apply: 'alpha',
      );
      const beta = rust.TypstCompletion(
        kind: rust.TypstCompletionKind.func(),
        label: 'beta',
        apply: 'beta',
      );
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
      expect(
        controller.selection.baseOffset,
        caretBefore,
        reason: 'arrow-down navigates the popup, not the caret',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // applyFromUtf16 (2) equals the cursor (2): an empty replace range, so
      // 'beta' is inserted right there rather than replacing anything.
      expect(
        controller.text,
        '#lbeta',
        reason: 'arrow-down moved the popup selection to the second item',
      );

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

    testWidgets(
      'enter applies the completion with its snippet stripped and the caret at the placeholder',
      (tester) async {
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
      },
    );

    testWidgets(
      'tab cycles to the next snippet stop without losing focus, even after typing at the first',
      (tester) async {
        // Two placeholders — the condition slot, then between the braces —
        // mirrors the reported case (an if/else snippet): apply it, type a
        // condition into the first stop, then Tab to the second.
        const ifSnippet = rust.TypstCompletion(
          kind: rust.TypstCompletionKind.syntax(),
          label: 'if',
          apply: 'if\${} {\${}}',
        );
        final fake = FakeRustSession()
          ..completionsToReturn = const [ifSnippet]
          ..applyFromUtf16ToReturn = 1;
        final session = TypstSession.forTesting(
          fake,
          const TypstSessionOptions(),
        );
        await session.compile('#i');
        final controller = TypstEditorController(session: session, text: '');
        final focusNode = FocusNode();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TypstCodeEditor(controller: controller, focusNode: focusNode),
                  // A second focusable widget: without one, Tab has nowhere
                  // else to go, so focusNode.hasFocus would stay true
                  // regardless of whether the key event was actually
                  // consumed — masking exactly the reported bug, where a
                  // *real* app has other controls (there, a toggle button)
                  // Tab lands on once Flutter's own focus traversal steals it.
                  TextButton(onPressed: () {}, child: const Text('elsewhere')),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        focusNode.requestFocus();
        await tester.pump();

        controller.value = const TextEditingValue(
          text: '#i',
          selection: TextSelection.collapsed(offset: 2),
        );
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.text('if'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(controller.text, '#if {}');
        expect(
          controller.selection,
          const TextSelection.collapsed(offset: 3),
          reason: 'caret on the first stop, right after "if"',
        );

        // Type at the first stop, as filling in the condition would — this is
        // exactly what makes a naive "match the remembered offset" design
        // fail: the second stop must shift by however much was typed.
        const typed = 'cond';
        controller.value = TextEditingValue(
          text: controller.text.replaceRange(3, 3, typed),
          selection: const TextSelection.collapsed(offset: 3 + typed.length),
        );
        await tester.pump();
        expect(controller.text, '#ifcond {}');

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(
          focusNode.hasFocus,
          isTrue,
          reason: 'Tab must not fall through to focus traversal here',
        );
        expect(
          controller.selection,
          const TextSelection.collapsed(offset: 9),
          reason:
              'second stop, between the curly braces, shifted by the 4 typed characters',
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'an implicit completions popup opening mid-snippet does not steal tab from advancing the snippet',
      (tester) async {
        // Typing at a stop is itself a text change with a collapsed
        // selection — exactly what _onControllerChanged schedules a fresh
        // *implicit* completions request for, same as any other typing.
        // That request can resolve before Tab is pressed, opening a real
        // (if incidental) popup. This reproduces that race: past the
        // completions debounce below, unlike the previous test (which
        // never advanced the fake clock far enough to give the debounce a
        // chance to fire).
        const ifSnippet = rust.TypstCompletion(
          kind: rust.TypstCompletionKind.syntax(),
          label: 'if',
          apply: 'if\${} {\${}}',
        );
        const trivialMatch = rust.TypstCompletion(
          kind: rust.TypstCompletionKind.syntax(),
          label: 'cond',
          apply: 'cond',
        );
        final fake = FakeRustSession()
          ..completionsToReturn = const [ifSnippet]
          ..applyFromUtf16ToReturn = 1;
        final session = TypstSession.forTesting(
          fake,
          const TypstSessionOptions(),
        );
        await session.compile('#i');
        final controller = TypstEditorController(session: session, text: '');
        final focusNode = FocusNode();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TypstCodeEditor(controller: controller, focusNode: focusNode),
                  TextButton(onPressed: () {}, child: const Text('elsewhere')),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        focusNode.requestFocus();
        await tester.pump();

        controller.value = const TextEditingValue(
          text: '#i',
          selection: TextSelection.collapsed(offset: 2),
        );
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.text('if'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(controller.selection, const TextSelection.collapsed(offset: 3));

        fake.completionsToReturn = const [trivialMatch];
        fake.applyFromUtf16ToReturn =
            3; // right after "if", where "cond" is being typed
        const typed = 'cond';
        controller.value = TextEditingValue(
          text: controller.text.replaceRange(3, 3, typed),
          selection: const TextSelection.collapsed(offset: 3 + typed.length),
        );
        await tester.pump(const Duration(milliseconds: 160));
        expect(
          find.text('cond'),
          findsWidgets,
          reason: 'the implicit popup is genuinely open at this point',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(focusNode.hasFocus, isTrue);
        expect(
          controller.selection,
          const TextSelection.collapsed(offset: 9),
          reason:
              'tab must advance the snippet, not apply whatever completion incidentally popped up',
        );
        expect(
          controller.text,
          '#ifcond {}',
          reason:
              'the incidental completion must not have been applied instead',
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'a completion result that arrives after the buffer moved on is not shown',
      (tester) async {
        final fake = FakeRustSession()
          ..completionsToReturn = const [lorem]
          ..applyFromUtf16ToReturn = 1
          ..completionsGate = Completer<void>();
        final session = TypstSession.forTesting(
          fake,
          const TypstSessionOptions(),
        );
        await session.compile('#l');
        final controller = TypstEditorController(session: session, text: '');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TypstCodeEditor(controller: controller)),
          ),
        );
        await tester.pump();

        controller.value = const TextEditingValue(
          text: '#l',
          selection: TextSelection.collapsed(offset: 2),
        );
        // Past _completionDebounceDelay: dispatches the request, which
        // reaches completions() (gated, held open) since lastCompiledSource
        // already matches '#l' from the compile() above — the "compile if
        // stale" step is a no-op here too.
        await tester.pump(const Duration(milliseconds: 160));

        // The buffer moves on (represented here by the native side's own
        // registered source changing, exactly the case
        // TypstSession.lastCompiledSource exists to detect) while the
        // completions() call above is still gated/in flight.
        await session.compile('#x');

        fake.completionsGate!.complete();
        await tester.pump(const Duration(milliseconds: 1));

        expect(
          find.text('lorem'),
          findsNothing,
          reason: 'stale result must not be shown',
        );

        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'typing a fuzzy (non-contiguous) match still finds the completion',
      (tester) async {
        const setStyle = rust.TypstCompletion(
          kind: rust.TypstCompletionKind.func(),
          label: 'set-style',
          apply: 'set-style(\${})',
        );
        // 's','e','t','s','t','y' is a subsequence of 'set-style' (skipping
        // the '-') but not a prefix of it — exercises the fuzzy fallback, not
        // the ordinary prefix filter.
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#setsty',
          cursor: 7,
          completions: const [setStyle],
          applyFromUtf16: 1,
        );

        expect(find.text('set-style'), findsOneWidget);

        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'a fuzzy match never outranks a real prefix match for the default selection',
      (tester) async {
        const prefixHit = rust.TypstCompletion(
          kind: rust.TypstCompletionKind.func(),
          label: 'style',
          apply: 'style',
        );
        // Both 'style' (a real prefix match for 'sty') and 'set-style' (only a
        // fuzzy match for 'sty' — s,t,y found in order, skipping 'e','-','l',
        // 'e') are candidates; the prefix match must still be first/selected.
        const setStyle = rust.TypstCompletion(
          kind: rust.TypstCompletionKind.func(),
          label: 'set-style',
          apply: 'set-style(\${})',
        );
        final focusNode = FocusNode();
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#sty',
          cursor: 4,
          completions: const [setStyle, prefixHit],
          applyFromUtf16: 1,
          focusNode: focusNode,
        );

        expect(find.text('style'), findsOneWidget);
        expect(find.text('set-style'), findsOneWidget);
        // The default (index 0) selection shows its detail underneath — see
        // defaultTypstCompletionsBuilder — so which one is selected is
        // observable without reaching into private state.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          controller.text,
          '#style',
          reason:
              'the real prefix match, not the fuzzy one, is applied by default',
        );
        focusNode.dispose();

        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets('a label that is not even a fuzzy match is excluded', (
      tester,
    ) async {
      const unrelated = rust.TypstCompletion(
        kind: rust.TypstCompletionKind.func(),
        label: 'rect',
        apply: 'rect(\${})',
      );
      final (_, session, controller) = await triggerCompletions(
        tester,
        text: '#setsty',
        cursor: 7,
        completions: const [unrelated],
        applyFromUtf16: 1,
      );

      expect(find.text('rect'), findsNothing);

      controller.dispose();
      await session.dispose();
    });
  });

  group('completion details panel', () {
    const lorem = rust.TypstCompletion(
      kind: rust.TypstCompletionKind.func(),
      label: 'lorem',
      apply: 'lorem(\${})',
    );
    const rectFunc = rust.TypstCompletion(
      kind: rust.TypstCompletionKind.func(),
      label: 'rect',
      apply: 'rect(\${})',
    );
    const letBinding = rust.TypstCompletion(
      kind: rust.TypstCompletionKind.syntax(),
      label: 'let binding',
      apply: 'let',
    );

    // Reuses the same `triggerCompletions` helper from the 'completion
    // popup' group above (defined in this same `main()`), which pre-compiles
    // and drives the implicit trigger through its debounce.
    Future<(FakeRustSession, TypstSession, TypstEditorController)>
    triggerCompletions(
      WidgetTester tester, {
      required String text,
      required int cursor,
      List<rust.TypstCompletion> completions = const [],
      int applyFromUtf16 = 1,
      FocusNode? focusNode,
      TypstDetailsBuilder? detailsBuilder,
      FakeRustSession? fake,
    }) async {
      final theFake = fake ?? FakeRustSession();
      theFake
        ..completionsToReturn = completions
        ..applyFromUtf16ToReturn = applyFromUtf16;
      final session = TypstSession.forTesting(
        theFake,
        const TypstSessionOptions(),
      );
      await session.compile(text);
      final controller = TypstEditorController(session: session, text: '');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCodeEditor(
              controller: controller,
              focusNode: focusNode,
              detailsBuilder: detailsBuilder,
            ),
          ),
        ),
      );
      await tester.pump();

      if (focusNode != null) {
        focusNode.requestFocus();
        await tester.pump();
      }

      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor),
      );
      await tester.pump(const Duration(milliseconds: 160));
      return (theFake, session, controller);
    }

    testWidgets(
      'a function item is fetched and its details shown via detailsBuilder',
      (tester) async {
        final fake = FakeRustSession()
          ..functionInfoToReturn = rust.TypstFunctionInfo(
            name: 'lorem',
            signature: _sig('lorem(count)'),
          );
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#l',
          cursor: 2,
          completions: const [lorem],
          applyFromUtf16: 2,
          fake: fake,
          detailsBuilder: (context, info) =>
              Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
        );

        expect(fake.functionInfoCalls, ['lorem']);
        expect(find.text('DETAILS:lorem(count)'), findsOneWidget);

        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'a non-function completion is never fetched and shows no details panel',
      (tester) async {
        final fake = FakeRustSession()
          ..functionInfoToReturn = rust.TypstFunctionInfo(
            name: 'lorem',
            signature: _sig('lorem(count)'),
          );
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#le',
          cursor: 3,
          completions: const [letBinding],
          applyFromUtf16: 3,
          fake: fake,
          detailsBuilder: (context, info) =>
              Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
        );

        expect(fake.functionInfoCalls, isEmpty);
        expect(find.textContaining('DETAILS:'), findsNothing);

        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets('with no detailsBuilder, nothing is ever fetched', (
      tester,
    ) async {
      final fake = FakeRustSession()
        ..functionInfoToReturn = rust.TypstFunctionInfo(
          name: 'lorem',
          signature: _sig('lorem(count)'),
        );
      final (_, session, controller) = await triggerCompletions(
        tester,
        text: '#l',
        cursor: 2,
        completions: const [lorem],
        applyFromUtf16: 2,
        fake: fake,
      );

      expect(
        fake.functionInfoCalls,
        isEmpty,
        reason: 'a caller who never opted in should pay no fetch cost',
      );

      controller.dispose();
      await session.dispose();
    });

    testWidgets(
      'functionInfo resolving to null leaves the completions popup showing normally',
      (tester) async {
        final fake = FakeRustSession(); // functionInfoToReturn defaults to null
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#l',
          cursor: 2,
          completions: const [lorem],
          applyFromUtf16: 2,
          fake: fake,
          detailsBuilder: (context, info) =>
              Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
        );

        expect(
          find.text('lorem'),
          findsOneWidget,
          reason: 'the completion list itself must not depend on this',
        );
        expect(find.textContaining('DETAILS:'), findsNothing);

        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'arrowing through items faster than fetches return shows only the last selection\'s details',
      (tester) async {
        final fake = FakeRustSession()
          ..functionInfoByLabel['lorem'] = rust.TypstFunctionInfo(
            name: 'lorem',
            signature: _sig('lorem(count)'),
          )
          ..functionInfoByLabel['rect'] = rust.TypstFunctionInfo(
            name: 'rect',
            signature: _sig('rect(width)'),
          )
          ..functionInfoGate = Completer<void>();
        final focusNode = FocusNode();
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#',
          cursor: 1,
          completions: const [lorem, rectFunc],
          focusNode: focusNode,
          fake: fake,
          detailsBuilder: (context, info) =>
              Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
        );
        // The initial-selection fetch for 'lorem' is in flight, gated.
        expect(fake.functionInfoCalls, ['lorem']);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        // Moving selection dispatches a second fetch, for 'rect' — also gated,
        // and now the *current* one (_detailsRequestId has advanced).
        expect(fake.functionInfoCalls, ['lorem', 'rect']);

        // Both requests resolve now, in the order they were made (lorem's
        // first) — only rect's result, the current selection's, should render.
        fake.functionInfoGate!.complete();
        await tester.pump(const Duration(milliseconds: 1));

        expect(find.text('DETAILS:rect(width)'), findsOneWidget);
        expect(
          find.text('DETAILS:lorem(count)'),
          findsNothing,
          reason:
              'the stale first fetch must not overwrite the later selection',
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'dismissing the popup mid-fetch does not reinsert it once the fetch resolves',
      (tester) async {
        final fake = FakeRustSession()
          ..functionInfoToReturn = rust.TypstFunctionInfo(
            name: 'lorem',
            signature: _sig('lorem(count)'),
          )
          ..functionInfoGate = Completer<void>();
        final focusNode = FocusNode();
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#l',
          cursor: 2,
          completions: const [lorem],
          applyFromUtf16: 2,
          focusNode: focusNode,
          fake: fake,
          detailsBuilder: (context, info) =>
              Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
        );
        expect(find.text('lorem'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(
          find.text('lorem'),
          findsNothing,
          reason: 'escape must have dismissed the popup',
        );

        // The in-flight functionInfo() call from before the dismissal resolves
        // only now.
        fake.functionInfoGate!.complete();
        await tester.pump(const Duration(milliseconds: 1));

        expect(
          find.text('lorem'),
          findsNothing,
          reason: 'a stale resolve must not reopen the popup',
        );
        expect(find.textContaining('DETAILS:'), findsNothing);

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    group('fallback to function details when typst-ide offers nothing', () {
      // Simulates a function whose only parameter is a variadic sink (e.g.
      // cetz's `set-style(..style)`) — typst-ide itself has no declared
      // param names to offer there, so `completions` comes back genuinely
      // empty (not narrowed-to-empty by prefix/fuzzy filtering).

      testWidgets(
        'shows the enclosing function\'s details instead of a silent empty popup',
        (tester) async {
          final fake = FakeRustSession()
            ..functionInfoToReturn = rust.TypstFunctionInfo(
              name: 'set-style',
              signature: _sig('set-style(..style)'),
            );
          final (_, session, controller) = await triggerCompletions(
            tester,
            text: '#set-style(',
            cursor: 11,
            completions: const [], // typst-ide offers nothing at all
            applyFromUtf16: 11,
            fake: fake,
            detailsBuilder: (context, info) =>
                Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
          );

          expect(find.text('DETAILS:set-style(..style)'), findsOneWidget);

          controller.dispose();
          await session.dispose();
        },
      );

      testWidgets('shows nothing when nothing resolves at the cursor either', (
        tester,
      ) async {
        final fake = FakeRustSession(); // functionInfoToReturn defaults to null
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: 'just some prose',
          cursor: 15,
          completions: const [],
          applyFromUtf16: 15,
          fake: fake,
          detailsBuilder: (context, info) =>
              Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
        );

        expect(find.textContaining('DETAILS:'), findsNothing);

        controller.dispose();
        await session.dispose();
      });

      testWidgets('never fetched at all without a detailsBuilder', (
        tester,
      ) async {
        final fake = FakeRustSession()
          ..functionInfoToReturn = rust.TypstFunctionInfo(
            name: 'set-style',
            signature: _sig('set-style(..style)'),
          );
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#set-style(',
          cursor: 11,
          completions: const [],
          applyFromUtf16: 11,
          fake: fake,
        );

        expect(fake.functionInfoCalls, isEmpty);

        controller.dispose();
        await session.dispose();
      });

      testWidgets(
        'does not trigger when a real (non-empty) list is just filtered down to empty',
        (tester) async {
          // completions is NOT empty here — typst-ide offered a real
          // candidate, it just doesn't match what's been typed. This must
          // not be confused with "typst-ide offered nothing at all".
          const unrelated = rust.TypstCompletion(
            kind: rust.TypstCompletionKind.func(),
            label: 'rect',
            apply: 'rect(\${})',
          );
          final fake = FakeRustSession()
            ..functionInfoToReturn = rust.TypstFunctionInfo(
              name: 'set-style',
              signature: _sig('set-style(..style)'),
            );
          final (_, session, controller) = await triggerCompletions(
            tester,
            text: '#zzz',
            cursor: 4,
            completions: const [unrelated],
            applyFromUtf16: 1,
            fake: fake,
            detailsBuilder: (context, info) =>
                Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
          );

          expect(
            fake.functionInfoCalls,
            isEmpty,
            reason: 'the fallback must not fire for a merely-filtered-out list',
          );
          expect(find.textContaining('DETAILS:'), findsNothing);

          controller.dispose();
          await session.dispose();
        },
      );

      testWidgets('escape dismisses the fallback-only popup', (tester) async {
        final fake = FakeRustSession()
          ..functionInfoToReturn = rust.TypstFunctionInfo(
            name: 'set-style',
            signature: _sig('set-style(..style)'),
          );
        final focusNode = FocusNode();
        final (_, session, controller) = await triggerCompletions(
          tester,
          text: '#set-style(',
          cursor: 11,
          completions: const [],
          applyFromUtf16: 11,
          fake: fake,
          focusNode: focusNode,
          detailsBuilder: (context, info) =>
              Text('DETAILS:${info.signature.map((t) => t.text).join()}'),
        );
        expect(find.text('DETAILS:set-style(..style)'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.textContaining('DETAILS:'), findsNothing);

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      });
    });
  });

  group('indent (Tab/Shift+Tab)', () {
    Future<(TypstSession, TypstEditorController, FocusNode)> mount(
      WidgetTester tester, {
      required String text,
      required TextSelection selection,
    }) async {
      final fake = FakeRustSession();
      final session = TypstSession.forTesting(
        fake,
        const TypstSessionOptions(),
      );
      final controller = TypstEditorController(session: session, text: text);
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCodeEditor(controller: controller, focusNode: focusNode),
          ),
        ),
      );
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();
      controller.selection = selection;
      await tester.pump();
      return (session, controller, focusNode);
    }

    Future<void> sendShiftTab(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }

    testWidgets('Tab with no selection inserts one indent unit at the caret', (
      tester,
    ) async {
      final (session, controller, focusNode) = await mount(
        tester,
        text: 'abcdef',
        selection: const TextSelection.collapsed(offset: 3),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.text, 'abc  def');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));

      focusNode.dispose();
      controller.dispose();
      await session.dispose();
    });

    testWidgets(
      'Tab with a multi-line selection indents every touched line and keeps them selected',
      (tester) async {
        final (session, controller, focusNode) = await mount(
          tester,
          text: 'one\ntwo\nthree',
          // Selects from inside "one" through inside "two" — "three" is
          // untouched.
          selection: const TextSelection(baseOffset: 1, extentOffset: 5),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(controller.text, '  one\n  two\nthree');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 3, extentOffset: 9),
          reason:
              'both indented lines stay selected, shifted by the inserted indent',
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets('Shift+Tab dedents the current line even with no selection', (
      tester,
    ) async {
      final (session, controller, focusNode) = await mount(
        tester,
        text: '    foo',
        selection: const TextSelection.collapsed(offset: 7),
      );

      await sendShiftTab(tester);
      await tester.pump();

      expect(
        controller.text,
        '  foo',
        reason: 'one indent unit (2 spaces) removed',
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 5));

      focusNode.dispose();
      controller.dispose();
      await session.dispose();
    });

    testWidgets(
      'Shift+Tab dedents every touched line for a selection, keeping it selected',
      (tester) async {
        final (session, controller, focusNode) = await mount(
          tester,
          text: '  one\n  two\nthree',
          selection: const TextSelection(baseOffset: 3, extentOffset: 9),
        );

        await sendShiftTab(tester);
        await tester.pump();

        expect(controller.text, 'one\ntwo\nthree');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 5),
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets('Shift+Tab on an unindented line does nothing', (tester) async {
      final (session, controller, focusNode) = await mount(
        tester,
        text: 'foo',
        selection: const TextSelection.collapsed(offset: 3),
      );

      await sendShiftTab(tester);
      await tester.pump();

      expect(controller.text, 'foo');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));

      focusNode.dispose();
      controller.dispose();
      await session.dispose();
    });
  });

  group('toggle comment (Ctrl+/)', () {
    Future<(TypstSession, TypstEditorController, FocusNode)> mount(
      WidgetTester tester, {
      required String text,
      required TextSelection selection,
    }) async {
      final fake = FakeRustSession();
      final session = TypstSession.forTesting(
        fake,
        const TypstSessionOptions(),
      );
      final controller = TypstEditorController(session: session, text: text);
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCodeEditor(controller: controller, focusNode: focusNode),
          ),
        ),
      );
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();
      controller.selection = selection;
      await tester.pump();
      return (session, controller, focusNode);
    }

    Future<void> sendCtrlSlash(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }

    testWidgets('the context menu shows a Toggle Comment entry', (
      tester,
    ) async {
      final (session, controller, focusNode) = await mount(
        tester,
        text: 'foo',
        selection: const TextSelection.collapsed(offset: 3),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TypstCodeEditor)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Toggle Comment'), findsOneWidget);

      focusNode.dispose();
      session.dispose();
    });

    testWidgets('comments the current line for a collapsed caret', (
      tester,
    ) async {
      final (session, controller, focusNode) = await mount(
        tester,
        text: 'foo',
        selection: const TextSelection.collapsed(offset: 3),
      );

      await sendCtrlSlash(tester);
      await tester.pump();

      expect(controller.text, '// foo');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));

      focusNode.dispose();
      controller.dispose();
      await session.dispose();
    });

    testWidgets(
      'uncomments the current line, dropping exactly one trailing space',
      (tester) async {
        final (session, controller, focusNode) = await mount(
          tester,
          text: '// foo',
          selection: const TextSelection.collapsed(offset: 6),
        );

        await sendCtrlSlash(tester);
        await tester.pump();

        expect(controller.text, 'foo');
        expect(controller.selection, const TextSelection.collapsed(offset: 3));

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'preserves indentation: the marker lands after leading whitespace',
      (tester) async {
        final (session, controller, focusNode) = await mount(
          tester,
          text: '  foo',
          selection: const TextSelection.collapsed(offset: 5),
        );

        await sendCtrlSlash(tester);
        await tester.pump();

        expect(controller.text, '  // foo');

        await sendCtrlSlash(tester);
        await tester.pump();

        expect(controller.text, '  foo', reason: 'toggling twice is a no-op');

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'comments every line a multi-line selection touches, blank lines left alone',
      (tester) async {
        final (session, controller, focusNode) = await mount(
          tester,
          text: 'one\n\ntwo',
          selection: const TextSelection(baseOffset: 0, extentOffset: 8),
        );

        await sendCtrlSlash(tester);
        await tester.pump();

        expect(controller.text, '// one\n\n// two');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 14),
          reason: 'selection expands to cover the now-longer commented text',
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'uncomments every line when all non-blank touched lines are already commented',
      (tester) async {
        final (session, controller, focusNode) = await mount(
          tester,
          text: '// one\n\n// two',
          selection: const TextSelection(baseOffset: 0, extentOffset: 14),
        );

        await sendCtrlSlash(tester);
        await tester.pump();

        expect(controller.text, 'one\n\ntwo');

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );

    testWidgets(
      'a mixed selection (only some lines commented) comments the rest instead of uncommenting',
      (tester) async {
        final (session, controller, focusNode) = await mount(
          tester,
          text: '// one\ntwo',
          selection: const TextSelection(baseOffset: 0, extentOffset: 10),
        );

        await sendCtrlSlash(tester);
        await tester.pump();

        expect(
          controller.text,
          '// // one\n// two',
          reason:
              'not every line was commented, so this comments, not uncomments',
        );

        focusNode.dispose();
        controller.dispose();
        await session.dispose();
      },
    );
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

    testWidgets('hovering over the source shows the tooltip content', (
      tester,
    ) async {
      final fake = FakeRustSession()
        ..tooltipToReturn = const rust.TypstTooltip.text(content: 'a heading');
      final session = TypstSession.forTesting(
        fake,
        const TypstSessionOptions(),
      );
      await session.compile('= Heading');
      final controller = TypstEditorController(
        session: session,
        text: '= Heading',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypstCodeEditor(controller: controller)),
        ),
      );
      await tester.pump();

      // A few pixels into the editor's top-left corner, where the first
      // line of text renders — see _onHover's vertical-bounds check for
      // why a point that isn't actually on a line (e.g. the center of an
      // expands:true editor much taller than one line) must not trigger a
      // request in the first place.
      await hoverTo(
        tester,
        tester.getTopLeft(find.byType(EditableText)) + const Offset(4, 4),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('a heading'), findsOneWidget);

      controller.dispose();
      await session.dispose();
    });

    testWidgets(
      'a hover result that arrives after the buffer moved on is not shown',
      (tester) async {
        final fake = FakeRustSession()
          ..tooltipToReturn = const rust.TypstTooltip.text(content: 'a heading')
          ..hoverGate = Completer<void>();
        final session = TypstSession.forTesting(
          fake,
          const TypstSessionOptions(),
        );
        await session.compile('= Heading');
        final controller = TypstEditorController(
          session: session,
          text: '= Heading',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TypstCodeEditor(controller: controller)),
          ),
        );
        await tester.pump();

        await hoverTo(
          tester,
          tester.getTopLeft(find.byType(EditableText)) + const Offset(4, 4),
        );
        await tester.pump(const Duration(milliseconds: 350));

        // The buffer moves on (represented here by the native side's own
        // registered source changing) while the hover() call above is still
        // gated/in flight.
        await session.compile('= Other');

        fake.hoverGate!.complete();
        await tester.pump(const Duration(milliseconds: 1));

        expect(
          find.text('a heading'),
          findsNothing,
          reason: 'stale hover result must not be shown',
        );

        controller.dispose();
        await session.dispose();
      },
    );
  });
}
