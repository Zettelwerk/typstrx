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
    // One line of text: "HELLOWORLD", 10 chars, 20pt wide each, at
    // y 100..120pt, starting at x 50pt. Plus one link over the text and an
    // internal link to page 3 at the bottom.
    const text = 'HELLOWORLD';
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
          bounds: const rust.RectPt(left: 50, top: 100, right: 250, bottom: 120),
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

  testWidgets('renders visible pages lazily, not the whole document',
      (tester) async {
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
      'as tiles render', (tester) async {
    final (session, _) = await makeSession();
    final controller = TypstViewerController();
    final scaleHistory = <double>[];
    controller.addListener(() => scaleHistory.add(controller.currentRasterScale));

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
  });

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
    await tester.sendEventToBinding(
      testPointer.scroll(const Offset(0, 100)),
    );
    await tester.pump();

    expect(controller.currentZoom, zoomBefore,
        reason: 'plain wheel must not zoom');
    expect(controller.visibleRect.top, greaterThan(topBefore),
        reason: 'plain wheel must pan the view downward');

    // Now with Control held: should zoom, not pan.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final topBeforeZoom = controller.visibleRect.top;
    await tester.sendEventToBinding(
      testPointer.scroll(const Offset(0, -100)),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.currentZoom, greaterThan(zoomBefore),
        reason: 'ctrl+wheel must zoom in');
    expect(controller.visibleRect.top, isNot(topBeforeZoom));
  });

  testWidgets('wheelZoomTrigger.always makes plain wheel zoom', (
    tester,
  ) async {
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
    await tester.sendEventToBinding(
      testPointer.scroll(const Offset(0, -100)),
    );
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

  testWidgets('goToPage scrolls and triggers renders for that page',
      (tester) async {
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

  testWidgets('zooming in renders a partial high-resolution tile',
      (tester) async {
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
    // virtual full page, offset into it, at tile scale (zoom 4 x dpr 3
    // clamped to maxRenderScale 4) => fullW = 595pt * 4 = 2380 px.
    final tiles = fake.renderedRegions
        .where((r) => r.w < r.fullW || r.h < r.fullH)
        .toList();
    expect(tiles, isNotEmpty);
    expect(tiles.first.fullW, closeTo(595 * 4, 8));
    expect(tiles.first.h, lessThan(tiles.first.fullH));
  });

  testWidgets('mouse drag selects text and controller exposes it',
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
    expect('HELLOWORLD', contains(controller.selectedText));
    expect(controller.selectedText.length, greaterThanOrEqualTo(4));

    controller.clearSelection();
    expect(controller.selectedText, isEmpty);
  });

  testWidgets('tapping links fires callback and navigates internal dests',
      (tester) async {
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

  testWidgets('recompile keeps old images until replacements arrive',
      (tester) async {
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
