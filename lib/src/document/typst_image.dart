import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A rendered image tile: straight RGBA8888 pixels, rows top-to-bottom.
class TypstImage {
  TypstImage({required this.width, required this.height, required this.pixels});

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// `width * height * 4` bytes of RGBA data.
  final Uint8List pixels;

  /// Decodes the raw pixels into a [ui.Image] for drawing on a canvas.
  ///
  /// The caller owns the returned image and must `dispose()` it.
  Future<ui.Image> createImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
