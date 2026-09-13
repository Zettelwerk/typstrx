import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typstrx/src/document/typst_session.dart';
import 'package:typstrx/src/rust/api/session.dart' as rust;
import 'package:typstrx/src/rust/api/types.dart' as rust;
import 'package:typstrx/typstrx.dart' hide TypstSession;

/// Fake bridge that "compiles" to 10 A4 pages and renders solid red pixels.
class FakeRustSession implements rust.TypstSession {
  var generation = 0;
  final renderedPages = <int>[];
  final renderedRegions =
      <({int page, int x, int y, int w, int h, int fullW, int fullH})>[];

  @override
  Future<rust.CompileResult> compile({required String source}) async {
    generation++;
    return rust.CompileResult(
      generation: BigInt.from(generation),
      success: true,
      pages: List.filled(10, const rust.PageInfo(widthPt: 595, heightPt: 842)),
      diagnostics: [],
      elapsedMs: BigInt.zero,
    );
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
    return rust.CompletionResult(
      generation: BigInt.zero,
      applyFromUtf16: 0,
      completions: const [],
    );
  }

  @override
  Future<rust.HoverResult> hover({required int cursorUtf16}) async {
    return rust.HoverResult(generation: BigInt.zero, tooltip: null);
  }

  @override
  Future<rust.FunctionInfoResult> functionInfo({
    required int cursorUtf16,
    required String label,
  }) async {
    return rust.FunctionInfoResult(generation: BigInt.zero, info: null);
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
    if (generation.toInt() != this.generation) {
      throw const rust.TypstrxError.stale();
    }
    renderedPages.add(pageIndex + 1);
    renderedRegions.add((
      page: pageIndex + 1,
      x: x,
      y: y,
      w: width,
      h: height,
      fullW: fullWidth,
      fullH: fullHeight,
    ));
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 0xff; // red
      pixels[i + 3] = 0xff;
    }
    return rust.RenderedRegion(width: width, height: height, pixels: pixels);
  }

  @override
  Future<rust.PageTextData> pageText({
    required BigInt generation,
    required int pageIndex,
  }) async {
    if (generation.toInt() != this.generation) {
      throw const rust.TypstrxError.stale();
    }
    // One line of text: "HELLO WORLD", 11 chars (including the space) 20pt
    // wide each, at y 100..120pt, starting at x 50pt. Plus one link over the
    // text and an internal link to page 3 at the bottom. Two separate words
    // (rather than one run) so a long-press selects a sub-range with real
    // room on both sides — needed to drag a handle all the way past the
    // other one, for the handle-crossing regression test below.
    const text = 'HELLO WORLD';
    return rust.PageTextData(
      fullText: text,
      charRects: [
        for (var i = 0; i < text.length; i++)
          rust.RectPt(
            left: 50.0 + i * 20,
            top: 100,
            right: 50.0 + (i + 1) * 20,
            bottom: 120,
          ),
      ],
      fragments: [
        rust.TextFragmentData(
          index: 0,
          length: text.length,
          bounds: const rust.RectPt(
            left: 50,
            top: 100,
            right: 250,
            bottom: 120,
          ),
        ),
      ],
      links: const [
        rust.LinkData(
          rect: rust.RectPt(left: 50, top: 300, right: 150, bottom: 320),
          url: 'https://typst.app',
          destPage: null,
          destXPt: null,
          destYPt: null,
        ),
        rust.LinkData(
          rect: rust.RectPt(left: 50, top: 400, right: 150, bottom: 420),
          url: null,
          destPage: 3,
          destXPt: 0,
          destYPt: 0,
        ),
      ],
    );
  }

  @override
  Future<Uint8List> exportPdf({required BigInt generation}) async {
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
  Future<(TypstSession, FakeRustSession)> makeSession() async {
    final fake = FakeRustSession();
    final session = TypstSession.forTesting(
      fake,
      const TypstSessionOptions(compileDebounce: Duration.zero),
    );
    await session.compile('ten pages');
    return (session, fake);
  }

  /// Pumps a frame, then lets real async work (page render + image decode)
  /// finish; image decoding never completes under the fake-async clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  testWidgets('renders visible pages lazily, not the whole document', (
    tester,
  ) async {
    final (session, fake) = await makeSession();
    final controller = TypstViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(
          session: session,
          controller: controller,
          params: const TypstViewerParams(
            renderDelay: Duration(milliseconds: 1),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(controller.isReady, isTrue);
    expect(fake.renderedPages, isNotEmpty);
    // Fit-width zoom shows roughly one page; with cache extent that is a few
    // pages — never all ten.
    expect(fake.renderedPages.toSet().length, lessThan(6));
    expect(controller.currentPageNumber, 1);
  });

  testWidgets(
    'currentRasterScale reflects the sharpest cached image and updates '
    'as tiles render',
    (tester) async {
      final (session, _) = await makeSession();
      final controller = TypstViewerController();
      final scaleHistory = <double>[];
      controller.addListener(
        () => scaleHistory.add(controller.currentRasterScale),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TypstViewer(
            session: session,
            controller: controller,
            params: const TypstViewerParams(
              renderDelay: Duration(milliseconds: 1),
            ),
          ),
        ),
      );
      await settle(tester);

      // Once the preview has rendered, the raster scale must be positive and
      // recorded via a controller notification (not just readable after the
      // fact) so a UI can display a live DPI readout.
      expect(controller.currentRasterScale, greaterThan(0));
      expect(scaleHistory, contains(controller.currentRasterScale));

      // Zooming in triggers a sharper tile; the reported scale must increase
      // to match once that tile finishes rendering.
      final scaleAtFitWidth = controller.currentRasterScale;
      controller.setZoom(4);
      await settle(tester);

      expect(controller.currentRasterScale, greaterThan(scaleAtFitWidth));
    },
  );

  testWidgets('plain mouse wheel pans, ctrl+wheel zooms', (tester) async {
    final (session, _) = await makeSession();
    final controller = TypstViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(session: session, controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final zoomBefore = controller.currentZoom;
    final topBefore = controller.visibleRect.top;

    final testPointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(testPointer.hover(const Offset(400, 300)));
    await tester.sendEventToBinding(testPointer.scroll(const Offset(0, 100)));
    await tester.pump();

    expect(
      controller.currentZoom,
      zoomBefore,
      reason: 'plain wheel must not zoom',
    );
    expect(
      controller.visibleRect.top,
      greaterThan(topBefore),
      reason: 'plain wheel must pan the view downward',
    );

    // Now with Control held: should zoom, not pan.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final topBeforeZoom = controller.visibleRect.top;
    await tester.sendEventToBinding(testPointer.scroll(const Offset(0, -100)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(
      controller.currentZoom,
      greaterThan(zoomBefore),
      reason: 'ctrl+wheel must zoom in',
    );
    expect(controller.visibleRect.top, isNot(topBeforeZoom));
  });

  testWidgets('wheelZoomTrigger.always makes plain wheel zoom', (tester) async {
    final (session, _) = await makeSession();
    final controller = TypstViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(
          session: session,
          controller: controller,
          params: const TypstViewerParams(
            wheelZoomTrigger: WheelZoomTrigger.always,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final zoomBefore = controller.currentZoom;
    final testPointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(testPointer.hover(const Offset(400, 300)));
    await tester.sendEventToBinding(testPointer.scroll(const Offset(0, -100)));
    await tester.pump();

    expect(controller.currentZoom, greaterThan(zoomBefore));
  });

  testWidgets('touch pinch zooms and one-finger drag pans', (tester) async {
    final (session, _) = await makeSession();
    final controller = TypstViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(session: session, controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // One-finger drag pans, doesn't zoom.
    final zoomBefore = controller.currentZoom;
    final topBefore = controller.visibleRect.top;
    final drag = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 20));
    // Several small steps: a single large jump gets entirely consumed by
    // the recognizer's touch-slop threshold, leaving nothing for onUpdate.
    for (var i = 0; i < 8; i++) {
      await drag.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 20));

    expect(controller.currentZoom, zoomBefore);
    expect(controller.visibleRect.top, greaterThan(topBefore));

    // Two-finger pinch zooms.
    final zoomBeforePinch = controller.currentZoom;
    final p1 = await tester.startGesture(
      const Offset(350, 300),
      kind: PointerDeviceKind.touch,
    );
    final p2 = await tester.startGesture(
      const Offset(450, 300),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < 8; i++) {
      await p1.moveBy(const Offset(-6, 0));
      await p2.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await p1.up();
    await p2.up();
    await tester.pump(const Duration(milliseconds: 20));

    expect(controller.currentZoom, greaterThan(zoomBeforePinch));
  });

  testWidgets(
    'a fast pan carries momentum past where the raw gesture alone would stop',
    (tester) async {
      final (session, _) = await makeSession();
      final controller = TypstViewerController();

      await tester.pumpWidget(
        MaterialApp(
          home: TypstViewer(session: session, controller: controller),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // tester.fling (not a hand-rolled drag+moveBy sequence) is what
      // reliably produces a velocity ScaleGestureRecognizer's tracker
      // recognizes as a fling — see _isFlingGesture in the SDK's
      // gestures/scale.dart, which silently reports Velocity.zero
      // otherwise, no matter how fast the on-screen movement looked.
      // tester.fling (not a hand-rolled drag+moveBy sequence) is what
      // reliably produces a velocity ScaleGestureRecognizer's tracker
      // recognizes as a fling — see _isFlingGesture in the SDK's
      // gestures/scale.dart, which silently reports Velocity.zero
      // otherwise, no matter how fast the on-screen movement looked.
      //
      // The moment-by-moment trajectory isn't asserted on here: an
      // AnimationController driven from a gesture callback is unreliable
      // to sample frame-by-frame under the widget-test fake clock (its
      // Ticker either sits at t=0 or jumps straight to "completed" in one
      // step, depending on exactly how the preceding gesture's own pump
      // calls left the fake scheduler clock — confirmed as a test-harness
      // artifact, not a real bug, by driving the same fling on a live
      // Linux build and watching it decelerate smoothly frame by frame).
      // pumpAndSettle, which just keeps pumping until nothing is
      // scheduled, reaches the fling's true final resting position
      // reliably even so, which is enough to prove momentum carried the
      // view well past whatever the raw gesture alone covered.
      final topAtRelease = controller.visibleRect.top;
      await tester.fling(
        find.byType(TypstViewer),
        const Offset(0, -300),
        3000,
        deviceKind: PointerDeviceKind.touch,
      );
      final topRightAfterGesture = controller.visibleRect.top;
      await tester.pumpAndSettle();
      expect(
        controller.visibleRect.top,
        greaterThan(topRightAfterGesture),
        reason:
            'momentum should carry the view further than the raw gesture alone moved it',
      );
      expect(controller.visibleRect.top, greaterThan(topAtRelease));
    },
  );

  testWidgets(
    'pinching past minScale stretches elastically instead of hard-clamping',
    (tester) async {
      final (session, _) = await makeSession();
      final controller = TypstViewerController();

      await tester.pumpWidget(
        MaterialApp(
          home: TypstViewer(
            session: session,
            controller: controller,
            params: const TypstViewerParams(minScale: 0.5, maxScale: 4),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      controller.setZoom(0.5);
      await tester.pump();
      expect(controller.currentZoom, 0.5);

      // Pinch inward hard, well past minScale — a wide starting span
      // pinched to a quarter of itself, well short of the fingers
      // crossing (which would start opening the span, hence the zoom,
      // back up again). This is a live gesture update, not an animation —
      // no fake-clock ticking involved, so (unlike the release-time
      // snap-back below) this part is reliably observable frame by frame
      // in a widget test.
      final p1 = await tester.startGesture(
        const Offset(200, 300),
        kind: PointerDeviceKind.touch,
      );
      final p2 = await tester.startGesture(
        const Offset(600, 300),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 20));
      for (var i = 0; i < 15; i++) {
        await p1.moveBy(const Offset(10, 0));
        await p2.moveBy(const Offset(-10, 0));
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(
        controller.currentZoom,
        lessThan(0.5),
        reason:
            'a hard clamp would have stopped exactly at minScale instead of stretching past it',
      );

      await p1.up();
      await p2.up();
      await tester.pumpAndSettle();
      expect(
        controller.currentZoom,
        moreOrLessEquals(0.5, epsilon: 0.01),
        reason: 'released, it should spring back to minScale',
      );
    },
  );

  testWidgets(
    'changing margin re-fits the view even without a viewport resize',
    (tester) async {
      final (session, _) = await makeSession();
      final controller = TypstViewerController();

      Widget build(double margin) => MaterialApp(
        home: TypstViewer(
          session: session,
          controller: controller,
          params: TypstViewerParams(margin: margin),
        ),
      );

      await tester.pumpWidget(build(8));
      await tester.pump(const Duration(milliseconds: 100));
      final zoomBefore = controller.currentZoom;

      // A bigger margin widens the document canvas the same fit-width
      // zoom is computed against, so a genuine re-fit must produce a
      // smaller zoom — with the viewport itself unchanged, the only other
      // trigger for a re-fit (see the LayoutBuilder in build()).
      await tester.pumpWidget(build(400));
      await tester.pump();
      expect(
        controller.currentZoom,
        lessThan(zoomBefore),
        reason: 'a larger margin should have triggered a re-fit to a smaller zoom',
      );
    },
  );

  testWidgets(
    'changing rasterBackgroundColor clears the cache and re-renders',
    (tester) async {
      final (session, fake) = await makeSession();
      final controller = TypstViewerController();

      Widget build(Color color) => MaterialApp(
        home: TypstViewer(
          session: session,
          controller: controller,
          params: TypstViewerParams(
            renderDelay: const Duration(milliseconds: 1),
            rasterBackgroundColor: color,
          ),
        ),
      );

      await tester.pumpWidget(build(const Color(0xffffffff)));
      await settle(tester);
      final renderedBefore = fake.renderedPages.length;
      expect(renderedBefore, greaterThan(0));

      await tester.pumpWidget(build(const Color(0xff000000)));
      await settle(tester);
      expect(
        fake.renderedPages.length,
        greaterThan(renderedBefore),
        reason: 'the stale-background cache entries should have been cleared and re-rendered',
      );
    },
  );

  testWidgets('goToPage scrolls and triggers renders for that page', (
    tester,
  ) async {
    final (session, fake) = await makeSession();
    final controller = TypstViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(
          session: session,
          controller: controller,
          params: const TypstViewerParams(
            renderDelay: Duration(milliseconds: 1),
          ),
        ),
      ),
    );
    await settle(tester);
    fake.renderedPages.clear();

    controller.goToPage(8);
    await settle(tester);

    expect(controller.currentPageNumber, 8);
    expect(fake.renderedPages, contains(8));
    expect(fake.renderedPages, isNot(contains(1)));
  });

  testWidgets('a tile survives leaving the viewport and is reused on return', (
    tester,
  ) async {
    final (session, fake) = await makeSession();
    final controller = TypstViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(
          session: session,
          controller: controller,
          params: const TypstViewerParams(
            renderDelay: Duration(milliseconds: 1),
          ),
        ),
      ),
    );
    await settle(tester);

    // Zoom in far enough that stage two applies, and settle on a specific
    // window of page 1 so the same window can be revisited exactly.
    controller.setZoom(4);
    controller.goToPage(1);
    await settle(tester);
    expect(
      fake.renderedRegions.where(
        (r) => r.page == 1 && (r.w < r.fullW || r.h < r.fullH),
      ),
      isNotEmpty,
      reason: 'zooming in should have produced a tile for page 1',
    );

    // Scroll away to another page, then back to the very same window.
    controller.goToPage(8);
    await settle(tester);
    fake.renderedRegions.clear();
    controller.goToPage(1);
    await settle(tester);

    // Page 1's tile was kept rather than pruned when it left the viewport, so
    // returning to the same window must not re-render it. Every render pass
    // used to drop tiles for pages that were no longer visible.
    expect(
      fake.renderedRegions.where(
        (r) => r.page == 1 && (r.w < r.fullW || r.h < r.fullH),
      ),
      isEmpty,
      reason: 'returning to a page should reuse its retained tile',
    );
  });

  testWidgets('setZoom keeps the zoom within bounds', (tester) async {
    final (session, _) = await makeSession();
    final controller = TypstViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(session: session, controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    controller.setZoom(100);
    expect(controller.currentZoom, 8.0); // default maxScale
    controller.setZoom(0.01);
    expect(controller.currentZoom, 0.25); // default minScale
  });

  testWidgets('zooming in renders a partial high-resolution tile', (
    tester,
  ) async {
    final (session, fake) = await makeSession();
    final controller = TypstViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(
          session: session,
          controller: controller,
          params: const TypstViewerParams(
            renderDelay: Duration(milliseconds: 1),
          ),
        ),
      ),
    );
    await settle(tester);
    fake.renderedRegions.clear();

    controller.setZoom(4);
    await settle(tester);

    // A partial render must have been issued: a window smaller than the
    // virtual full page, offset into it, at tile scale. Zoom 4 x dpr 3 = 12
    // px/pt asks for more than maxRenderDpi allows, so the tile clamps to that
    // ceiling — expressed via the param so raising the default doesn't rot
    // this expectation.
    const params = TypstViewerParams();
    final clampedScale = params.maxRenderDpi / 72;
    final tiles = fake.renderedRegions
        .where((r) => r.w < r.fullW || r.h < r.fullH)
        .toList();
    expect(tiles, isNotEmpty);
    expect(tiles.first.fullW, closeTo(595 * clampedScale, 8));
    expect(tiles.first.h, lessThan(tiles.first.fullH));
  });

  testWidgets('mouse drag selects text and controller exposes it', (
    tester,
  ) async {
    final (session, _) = await makeSession();
    final controller = TypstViewerController();
    final changes = <TypstTextSelection?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(
          session: session,
          controller: controller,
          params: TypstViewerParams(
            renderDelay: const Duration(milliseconds: 1),
            showSelectionToolbar: false,
            onSelectionChanged: changes.add,
          ),
        ),
      ),
    );
    await settle(tester); // loads page text for visible pages

    // Page 1 starts at doc (8, 8); text row at page-local y 100..120,
    // chars from x 50. Zoom is fit-width (800 / 611).
    const zoom = 800 / 611;
    Offset docToView(Offset doc) => Offset(doc.dx * zoom, doc.dy * zoom);
    final from = docToView(const Offset(8 + 55, 8 + 110));
    final to = docToView(const Offset(8 + 145, 8 + 110));

    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 30));

    expect(controller.selectedText, isNotEmpty);
    expect('HELLO WORLD', contains(controller.selectedText));
    expect(controller.selectedText.length, greaterThanOrEqualTo(4));
    expect(controller.selection, isNotNull);
    expect(controller.selection!.text, controller.selectedText);
    expect(controller.selection!.start.pageNumber, 1);
    expect(controller.selection!.rects, isNotEmpty);
    expect(changes.last, controller.selection);

    controller.clearSelection();
    expect(controller.selectedText, isEmpty);
    expect(controller.selection, isNull);
    expect(changes.last, isNull);
  });

  testWidgets(
    'long-press selects a word on touch and shows big handles + a magnifier while dragging one',
    (tester) async {
      final (session, _) = await makeSession();
      final controller = TypstViewerController();

      await tester.pumpWidget(
        MaterialApp(
          home: TypstViewer(
            session: session,
            controller: controller,
            params: const TypstViewerParams(
              renderDelay: Duration(milliseconds: 1),
            ),
          ),
        ),
      );
      await settle(tester); // loads page text for visible pages

      // Same text row as the mouse-drag test above.
      const zoom = 800 / 611;
      Offset docToView(Offset doc) => Offset(doc.dx * zoom, doc.dy * zoom);
      final wordPoint = docToView(const Offset(8 + 60, 8 + 110));

      final press = await tester.startGesture(
        wordPoint,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(
        const Duration(milliseconds: 600),
      ); // past the long-press timeout
      await press.up();
      await tester.pump();

      expect(
        controller.selectedText,
        isNotEmpty,
        reason: 'long-press should have selected the word under it',
      );

      // The two selection handles: identified structurally (a pan-draggable
      // GestureDetector), not by exact pixel position, since that's an
      // implementation detail of char-rect geometry this test shouldn't
      // need to reproduce.
      bool isHandle(Widget w) =>
          w is GestureDetector && w.onPanStart != null && w.onPanUpdate != null;
      final handles = find.byWidgetPredicate(isHandle);
      expect(handles, findsNWidgets(2));

      expect(
        find.byType(RawMagnifier),
        findsNothing,
        reason:
            'the magnifier only shows once a handle is actually being dragged',
      );

      final handleCenter = tester.getCenter(handles.first);
      final drag = await tester.startGesture(
        handleCenter,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveBy(const Offset(15, 0));
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        find.byType(RawMagnifier),
        findsOneWidget,
        reason: 'shown while a handle is being dragged',
      );

      // The magnifier floats clear above the finger (~1cm above the actual
      // text row, not merely resting on top of it) rather than nearly
      // touching it. `handleCenter` (a natural touch point on the visible
      // flag's bounding box, not literally the row itself) is off from the
      // row center by a few px — for the start handle specifically, whose
      // flag hangs *above* the row, grabbing at the box's geometric center
      // eats into that clearance more than for the end handle (see below):
      // still a real, positive gap, just not the full ~1cm from this exact
      // synthetic grab point. See the row-locking test below for a precise
      // check pinned to the row's own center.
      final fingerY = handleCenter.dy;
      final magnifierBottom = tester.getRect(find.byType(RawMagnifier)).bottom;
      expect(
        fingerY - magnifierBottom,
        greaterThan(5),
        reason:
            'the magnifier should sit clear of the fingertip, not touch or overlap it',
      );

      await drag.up();
      await tester.pump(const Duration(milliseconds: 20));

      expect(
        find.byType(RawMagnifier),
        findsNothing,
        reason: 'hidden again once the drag ends',
      );
    },
  );

  testWidgets(
    'the magnifier tracks the actual text row, not wherever within the flag '
    'the finger first grabbed it',
    (tester) async {
      final (session, _) = await makeSession();
      final controller = TypstViewerController();

      await tester.pumpWidget(
        MaterialApp(
          home: TypstViewer(
            session: session,
            controller: controller,
            params: const TypstViewerParams(
              renderDelay: Duration(milliseconds: 1),
            ),
          ),
        ),
      );
      await settle(tester);

      const zoom = 800 / 611;
      Offset docToView(Offset doc) => Offset(doc.dx * zoom, doc.dy * zoom);
      final wordPoint = docToView(const Offset(8 + 60, 8 + 110));

      final press = await tester.startGesture(
        wordPoint,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await press.up();
      await tester.pump();

      bool isHandle(Widget w) =>
          w is GestureDetector && w.onPanStart != null && w.onPanUpdate != null;
      final handles = find.byWidgetPredicate(isHandle);
      expect(handles, findsNWidgets(2));

      // The end handle's flag hangs below-right of the actual text edge
      // (see typst_viewer_selection.dart), so its own top-left corner is
      // that edge — grabbing at the flag's visual center (as a real finger
      // naturally would) touches down ~15px below-right of it. The row's
      // own *center* (per the fixture: chars are 20pt tall, so 10pt/13
      // view px above that bottom edge) is the value that actually
      // matters — not the edge itself, which sits at the very bottom of
      // the character's box, past its visible ink.
      final endHandleRect = tester.getRect(handles.last);
      final rowBottom = endHandleRect.topLeft.dy;
      final rowCenter = rowBottom - 10 * zoom;
      final grabPoint = endHandleRect.center;

      final drag = await tester.startGesture(
        grabPoint,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 20));
      // Horizontal-only movement: the finger's height above the true text
      // row never changes from wherever it first grabbed.
      await drag.moveBy(const Offset(15, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Without compensating for the grab offset, the magnifier centers on
      // the raw (still ~15px low) finger position instead of the row, and
      // ends up showing the line below the actual selection. Without also
      // locking to the row's *center* (rather than the edge the grab
      // offset is itself defined against), it would instead sample the
      // very bottom of the character's box — past the ink, into blank
      // leading space.
      final magnifierBottom = tester.getRect(find.byType(RawMagnifier)).bottom;
      expect(
        magnifierBottom,
        moreOrLessEquals(rowCenter - 39, epsilon: 3),
        reason:
            'the magnifier should stay pinned to the text row the finger grabbed, not drift by the grab offset',
      );

      // Independent of the above: whatever's shown at the magnifier
      // widget's own on-screen *center* must be the row's center —
      // `RawMagnifier.focalPointOffset` is measured from that center (its
      // own doc comment's worked example), not the widget's top edge.
      // Getting this wrong by `magnifierSize.height / 2` (an earlier
      // version of this code did) shows roughly the bottom half of the
      // selection highlight instead of all of it, centered.
      final magnifier = tester.widget<RawMagnifier>(find.byType(RawMagnifier));
      final magnifierCenterY = tester
          .getRect(find.byType(RawMagnifier))
          .center
          .dy;
      expect(
        magnifierCenterY + magnifier.focalPointOffset.dy,
        moreOrLessEquals(rowCenter, epsilon: 0.5),
        reason:
            'the magnifier should show content centered on the row, not shifted down by half its own height',
      );

      await drag.up();
    },
  );

  testWidgets(
    'grabbing a handle off-anchor extends the selection by the actual net '
    'finger movement, not the raw touch position',
    (tester) async {
      final (session, _) = await makeSession();
      final controller = TypstViewerController();

      await tester.pumpWidget(
        MaterialApp(
          home: TypstViewer(
            session: session,
            controller: controller,
            params: const TypstViewerParams(
              renderDelay: Duration(milliseconds: 1),
            ),
          ),
        ),
      );
      await settle(tester);

      const zoom = 800 / 611;
      Offset docToView(Offset doc) => Offset(doc.dx * zoom, doc.dy * zoom);
      final wordPoint = docToView(const Offset(8 + 60, 8 + 110));
      final press = await tester.startGesture(
        wordPoint,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await press.up();
      await tester.pump();
      expect(controller.selectedText, 'HELLO');

      bool isHandle(Widget w) =>
          w is GestureDetector && w.onPanStart != null && w.onPanUpdate != null;
      final handles = find.byWidgetPredicate(isHandle);
      // The end handle's flag hangs below-right of the text edge, so its
      // visual center — where a real finger naturally lands — is off the
      // true anchor both vertically (already covered above) and
      // horizontally.
      final grabPoint = tester.getRect(handles.last).center;

      final drag = await tester.startGesture(
        grabPoint,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveBy(const Offset(15, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Without re-adding the horizontal grab offset each frame the same
      // way as the vertical one, the hit-tested character would land one
      // column further right than this net finger movement actually
      // implies ('HELLO W' instead of 'HELLO ').
      expect(controller.selectedText, 'HELLO ');

      await drag.up();
    },
  );

  testWidgets(
    'dragging a handle only notifies selection listeners on an actual change',
    (tester) async {
      final (session, _) = await makeSession();
      final controller = TypstViewerController();
      var notifications = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: TypstViewer(
            session: session,
            controller: controller,
            params: TypstViewerParams(onSelectionChanged: (_) => notifications++),
          ),
        ),
      );
      await settle(tester);

      const zoom = 800 / 611;
      Offset docToView(Offset doc) => Offset(doc.dx * zoom, doc.dy * zoom);
      // "HELLO" (chars 0..5), with "WORLD" free to its right — room for
      // the end handle to actually move into a new character.
      final wordPoint = docToView(const Offset(8 + 60, 8 + 110));
      final press = await tester.startGesture(wordPoint, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 600));
      await press.up();
      await tester.pump();
      expect(controller.selectedText, 'HELLO');

      bool isHandle(Widget w) => w is GestureDetector && w.onPanStart != null && w.onPanUpdate != null;
      final handles = find.byWidgetPredicate(isHandle);
      final endHandleCenter = tester.getCenter(handles.last);

      final drag = await tester.startGesture(endHandleCenter, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 20));
      // One real move, extending the selection into "WORLD".
      final target = endHandleCenter + const Offset(60, 0);
      await drag.moveTo(target);
      await tester.pump(const Duration(milliseconds: 10));
      expect(notifications, greaterThan(0), reason: 'an actual selection change should notify');
      final afterRealMove = notifications;

      // Several more frames landing on that exact same point (e.g. a
      // finger holding still, or jitter that resolves to the same
      // character) — none of these introduce any further change, so none
      // should notify again.
      for (var i = 0; i < 5; i++) {
        await drag.moveTo(target);
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(
        notifications,
        afterRealMove,
        reason: 'repeating the same resolved position should not fire redundant selection notifications',
      );

      await drag.up();
    },
  );

  testWidgets(
    'dragging the end handle past the start handle keeps a valid (swapped) selection',
    (tester) async {
      final (session, _) = await makeSession();
      final controller = TypstViewerController();

      await tester.pumpWidget(
        MaterialApp(
          home: TypstViewer(
            session: session,
            controller: controller,
            params: const TypstViewerParams(
              renderDelay: Duration(milliseconds: 1),
            ),
          ),
        ),
      );
      await settle(tester);

      const zoom = 800 / 611;
      Offset docToView(Offset doc) => Offset(doc.dx * zoom, doc.dy * zoom);

      // Long-press "R" in "WORLD" (chars 6..11) to select that whole word,
      // leaving "HELLO" (chars 0..5) untouched to its left — room to drag
      // the end handle all the way past the (fixed) start handle.
      final wordPoint = docToView(const Offset(8 + 220, 8 + 110));
      final press = await tester.startGesture(
        wordPoint,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await press.up();
      await tester.pump();
      expect(controller.selectedText, 'WORLD');

      bool isHandle(Widget w) =>
          w is GestureDetector && w.onPanStart != null && w.onPanUpdate != null;
      final handles = find.byWidgetPredicate(isHandle);
      expect(handles, findsNWidgets(2));
      final endHandleCenter = tester.getCenter(handles.last);

      // Drag the end handle, in several incremental steps (reproducing the
      // multi-frame drift the original bug needed to manifest), all the
      // way past the fixed start handle and into "HELLO".
      final drag = await tester.startGesture(
        endHandleCenter,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 20));
      for (final doc in [
        const Offset(8 + 180, 8 + 110),
        const Offset(8 + 130, 8 + 110),
        const Offset(8 + 100, 8 + 110),
      ]) {
        await drag.moveTo(docToView(doc));
        await tester.pump(const Duration(milliseconds: 20));
      }

      // The selection must still be alive and span the whole crossed
      // range — not collapsed to a near-nothing sliver, which is exactly
      // what the bug this guards against did: re-deriving "the other,
      // fixed endpoint" from the swap-aware normalized selection every
      // frame lost track of the true fixed point after crossing.
      expect(controller.selectedText, isNotEmpty);
      expect(
        controller.selectedText.length,
        greaterThanOrEqualTo(3),
        reason: 'a 1-2 char selection here is the collapse-to-nothing bug',
      );
      expect(
        find.byWidgetPredicate(isHandle),
        findsNWidgets(2),
        reason: 'both handles still render post-crossing',
      );

      await drag.up();
      await tester.pump(const Duration(milliseconds: 20));
    },
  );

  testWidgets('tapping links fires callback and navigates internal dests', (
    tester,
  ) async {
    final (session, _) = await makeSession();
    final controller = TypstViewerController();
    final tappedLinks = <TypstLink>[];

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(
          session: session,
          controller: controller,
          params: TypstViewerParams(
            renderDelay: const Duration(milliseconds: 1),
            onLinkTap: tappedLinks.add,
          ),
        ),
      ),
    );
    await settle(tester);

    const zoom = 800 / 611;
    // URL link at page-local (50..150, 300..320). The tap only resolves
    // after the double-tap recognizer's timeout.
    await tester.tapAt(const Offset((8 + 100) * zoom, (8 + 310) * zoom));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tappedLinks, hasLength(1));
    expect(tappedLinks.first.url, Uri.parse('https://typst.app'));

    // Internal link to page 3 at page-local (50..150, 400..420).
    await tester.tapAt(const Offset((8 + 100) * zoom, (8 + 410) * zoom));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(tappedLinks, hasLength(2));
    expect(controller.currentPageNumber, 3);
  });

  testWidgets('recompile keeps old images until replacements arrive', (
    tester,
  ) async {
    final (session, fake) = await makeSession();

    await tester.pumpWidget(
      MaterialApp(
        home: TypstViewer(
          session: session,
          params: const TypstViewerParams(
            renderDelay: Duration(milliseconds: 1),
          ),
        ),
      ),
    );
    await settle(tester);
    final before = fake.renderedPages.length;
    expect(before, greaterThan(0));

    await session.compile('changed source');
    await settle(tester);

    // New generation triggered re-renders of the visible pages.
    expect(fake.renderedPages.length, greaterThan(before));
  });
}
