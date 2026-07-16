import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typstrx/src/document/typst_session.dart';
import 'package:typstrx/src/rust/api/session.dart' as rust;
import 'package:typstrx/src/rust/api/types.dart' as rust;
import 'package:typstrx/typstrx.dart' hide TypstSession;

/// Fake bridge that "compiles" to 10 A4 pages and renders solid red pixels.
class FakeRustSession implements rust.TypstSession {
  var generation = 0;
  final renderedPages = <int>[];

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
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 0xff; // red
      pixels[i + 3] = 0xff;
    }
    return rust.RenderedRegion(width: width, height: height, pixels: pixels);
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
