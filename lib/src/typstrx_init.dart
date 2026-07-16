import 'rust/frb_generated.dart';

/// Global library initialization for typstrx.
abstract final class Typstrx {
  /// Loads the native library and initializes the Rust bridge.
  ///
  /// Must be called once (e.g. in `main`) before creating a [TypstSession].
  /// Calling it again is a no-op.
  static Future<void> init() async {
    if (RustLib.instance.initialized) return;
    await RustLib.init();
  }
}
