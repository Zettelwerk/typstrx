// Not a correctness test — measures the pure Dart-side costs in the FFI
// render path: the Uint8List copy that FRB's SseCodec performs when
// deserializing the pixel buffer, and the GPU texture upload cost of
// decodeImageFromPixels. Run manually:
//   flutter test test/perf/copy_overhead_test.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Realistic RGBA8888 buffer sizes taken from the render_bench.rs Rust
/// benchmarks (rust/tests/render_bench.rs) for a text-heavy A4 page at
/// various scales, plus the fixed 900x700 tile size used there.
final _cases = <String, (int, int)>{
  '1.0x full page (595x842)': (595, 842),
  '2.0x full page (1191x1684)': (1191, 1684),
  '4.0x full page (2381x3368)': (2381, 3368),
  '8.0x full page (4762x6735)': (4762, 6735),
  'tile (900x700)': (900, 700),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in _cases.entries) {
    final (width, height) = entry.value;
    final byteLength = width * height * 4;
    final mb = byteLength / (1024 * 1024);

    test(
      '${entry.key} (${mb.toStringAsFixed(1)} MB): Uint8List.fromList copy',
      () {
        // Simulate the arrived-but-not-yet-copied view, same as
        // ReadBuffer.getUint8List does internally.
        final source = Uint8List(byteLength);
        for (var i = 0; i < byteLength; i += 4096) {
          source[i] = 1; // touch pages so allocation isn't lazy/zero-fill-only
        }

        const iterations = 10;
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < iterations; i++) {
          final copy = Uint8List.fromList(source);
          // Prevent the copy from being optimized away.
          if (copy.isEmpty) throw StateError('unreachable');
        }
        stopwatch.stop();
        final perCopyUs = stopwatch.elapsedMicroseconds / iterations;
        // ignore: avoid_print
        print(
          '  copy: ${(perCopyUs / 1000).toStringAsFixed(3)} ms '
          '(${(mb / (perCopyUs / 1e6)).toStringAsFixed(0)} MB/s)',
        );
      },
    );

    test('${entry.key} (${mb.toStringAsFixed(1)} MB): '
        'decodeImageFromPixels (GPU upload)', () async {
      final pixels = Uint8List(byteLength);
      const iterations = 5;
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          pixels,
          width,
          height,
          ui.PixelFormat.rgba8888,
          completer.complete,
        );
        final image = await completer.future;
        image.dispose();
      }
      stopwatch.stop();
      final perDecodeUs = stopwatch.elapsedMicroseconds / iterations;
      // ignore: avoid_print
      print('  decode: ${(perDecodeUs / 1000).toStringAsFixed(3)} ms');
    });
  }
}
