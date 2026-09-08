import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:typstrx/src/document/typst_session.dart';
import 'package:typstrx/src/rust/api/session.dart' as rust;
import 'package:typstrx/src/rust/api/types.dart' as rust;

/// A fake bridge session so scheduler behavior is testable without the
/// native library.
class FakeRustSession implements rust.TypstSession {
  final compiledSources = <String>[];
  var generation = 0;

  /// Compilations block until [finishCompile] is called when set.
  Completer<void>? gate;

  @override
  Future<rust.CompileResult> compile({required String source}) async {
    compiledSources.add(source);
    if (gate != null) await gate!.future;
    generation++;
    return rust.CompileResult(
      generation: BigInt.from(generation),
      success: true,
      pages: [const rust.PageInfo(widthPt: 595, heightPt: 842)],
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
    return rust.RenderedRegion(
      width: width,
      height: height,
      pixels: Uint8List(width * height * 4),
    );
  }

  @override
  Future<rust.PageTextData> pageText({
    required BigInt generation,
    required int pageIndex,
  }) async {
    if (generation.toInt() != this.generation) {
      throw const rust.TypstrxError.stale();
    }
    return const rust.PageTextData(
      fullText: '',
      charRects: [],
      fragments: [],
      links: [],
    );
  }

  @override
  Future<rust.HighlightNode> highlight({required String source}) async {
    return rust.HighlightNode(tag: null, text: source, children: const []);
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

TypstSession makeSession(FakeRustSession fake, {Duration? debounce}) {
  return TypstSession.forTesting(
    fake,
    TypstSessionOptions(
      compileDebounce: debounce ?? const Duration(milliseconds: 5),
    ),
  );
}

void main() {
  test('compile returns a document with pages', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    final result = await session.compile('hello');
    expect(result.success, isTrue);
    expect(result.document!.pages, hasLength(1));
    expect(result.document!.pages.first.pageNumber, 1);
    expect(result.generation, 1);
    expect(session.document, result.document);
  });

  test('updateSource debounces rapid edits into one compile', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake, debounce: const Duration(milliseconds: 20));
    session.updateSource('a');
    session.updateSource('ab');
    session.updateSource('abc');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fake.compiledSources, ['abc']);
  });

  test('updateSource coalesces edits arriving during a running compile',
      () async {
    final fake = FakeRustSession();
    final session = makeSession(fake, debounce: Duration.zero);

    fake.gate = Completer<void>();
    session.updateSource('first');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fake.compiledSources, ['first']);

    // While 'first' is compiling, several newer sources arrive.
    session.updateSource('second');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    session.updateSource('third');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    fake.gate!.complete();
    fake.gate = null;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // 'second' was superseded by 'third' before it ever started.
    expect(fake.compiledSources, ['first', 'third']);
  });

  test('documents stream emits only successful compiles', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    final documents = <int>[];
    session.documents.listen((doc) => documents.add(doc.generation));
    await session.compile('one');
    await session.compile('two');
    await Future<void>.delayed(Duration.zero);
    expect(documents, [1, 2]);
  });

  test('stale render returns null from page.render', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    final first = await session.compile('one');
    await session.compile('two');
    final image = await first.document!.pages.first.render();
    expect(image, isNull);
  });

  test('dispose stops scheduled work and further calls throw', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake, debounce: const Duration(milliseconds: 20));
    session.updateSource('pending');
    await session.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fake.compiledSources, isEmpty);
    expect(fake.isDisposed, isTrue);
    expect(() => session.compile('x'), throwsStateError);
  });
}
