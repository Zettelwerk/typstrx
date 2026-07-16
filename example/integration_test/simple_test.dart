import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typstrx/typstrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await Typstrx.init());

  test('compiles and renders a document', () async {
    final session = await TypstSession.create(
      options: const TypstSessionOptions(allowPackageDownload: false),
    );
    final result = await session.compile('= Hello, *world*!');
    expect(result.success, isTrue);
    expect(result.document, isNotNull);
    expect(result.document!.pages, hasLength(1));

    final page = result.document!.pages.first;
    expect(page.width, closeTo(595.28, 0.1));

    final image = await page.render();
    expect(image, isNotNull);
    expect(image!.pixels.length, image.width * image.height * 4);

    // Some pixel must be non-white (the rendered text).
    final pixels = image.pixels;
    var hasInk = false;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i] != 0xff || pixels[i + 1] != 0xff || pixels[i + 2] != 0xff) {
        hasInk = true;
        break;
      }
    }
    expect(hasInk, isTrue);

    await session.dispose();
  });

  test('reports diagnostics for broken source', () async {
    final session = await TypstSession.create(
      options: const TypstSessionOptions(allowPackageDownload: false),
    );
    final result = await session.compile('#let x = ');
    expect(result.success, isFalse);
    expect(result.diagnostics, isNotEmpty);
    expect(result.diagnostics.first.severity, TypstDiagnosticSeverity.error);
    await session.dispose();
  });
}
