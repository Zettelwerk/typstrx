// Not a correctness test — measures the full Dart-side round trip of
// TypstPage.render() (FFI dispatch + Rust rasterization + SseCodec
// deserialize/copy + TypstImage.createImage's GPU upload) through the real
// native library, for comparison against:
//   - rust/tests/render_bench.rs (pure Rust rasterization, no FFI/Dart)
//   - test/perf/copy_overhead_test.dart (pure Dart copy + GPU upload, no FFI)
// The gap between this total and the sum of those two isolates FFI
// dispatch/serialization overhead specifically.
//
// Run with: flutter test integration_test/render_roundtrip_bench_test.dart -d linux
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typstrx/typstrx.dart';

// Same content as rust/tests/render_bench.rs's TEXT_HEAVY constant, for an
// apples-to-apples comparison against those pure-Rust numbers.
const _textHeavy = '= A Typical Document\n#lorem(400)';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await Typstrx.init());

  test('full page render round trip across scales', () async {
    final session = await TypstSession.create(
      options: const TypstSessionOptions(allowPackageDownload: false),
    );
    final result = await session.compile(_textHeavy);
    expect(result.success, isTrue);
    final page = result.document!.pages.first;

    // Debug-mode native lib (what `flutter test` builds) is far slower than
    // release for compute-heavy rasterization, so keep this to modest
    // scales/iterations — the point is comparing against the debug-mode
    // Rust-only benchmark below, not absolute release-mode numbers.
    for (final scale in [1.0, 2.0]) {
      const warmup = 1;
      const iterations = 3;
      var totalUs = 0;
      for (var i = 0; i < warmup + iterations; i++) {
        final stopwatch = Stopwatch()..start();
        final image = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
        );
        stopwatch.stop();
        expect(image, isNotNull);
        if (i >= warmup) totalUs += stopwatch.elapsedMicroseconds;
      }
      final avgMs = totalUs / iterations / 1000;
      // ignore: avoid_print
      print(
        '  ${scale.toStringAsFixed(1)}x full page round trip: '
        '${avgMs.toStringAsFixed(2)} ms',
      );
    }

    await session.dispose();
  });

  test('tile (900x700) render round trip across scales', () async {
    final session = await TypstSession.create(
      options: const TypstSessionOptions(allowPackageDownload: false),
    );
    final result = await session.compile(_textHeavy);
    expect(result.success, isTrue);
    final page = result.document!.pages.first;

    for (final scale in [1.0, 2.0, 4.0, 8.0]) {
      final fullW = page.width * scale;
      final fullH = page.height * scale;
      final tileW = fullW < 900 ? fullW.round() : 900;
      final tileH = fullH < 700 ? fullH.round() : 700;

      const warmup = 1;
      const iterations = 5;
      var totalUs = 0;
      for (var i = 0; i < warmup + iterations; i++) {
        final stopwatch = Stopwatch()..start();
        final image = await page.render(
          width: tileW,
          height: tileH,
          fullWidth: fullW,
          fullHeight: fullH,
        );
        stopwatch.stop();
        expect(image, isNotNull);
        if (i >= warmup) totalUs += stopwatch.elapsedMicroseconds;
      }
      final avgMs = totalUs / iterations / 1000;
      // ignore: avoid_print
      print(
        '  ${scale.toStringAsFixed(1)}x tile (${tileW}x$tileH) round trip: '
        '${avgMs.toStringAsFixed(2)} ms',
      );
    }

    await session.dispose();
  });
}
