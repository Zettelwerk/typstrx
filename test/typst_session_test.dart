import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:typstrx/src/document/typst_completion.dart';
import 'package:typstrx/src/document/typst_folding_range.dart';
import 'package:typstrx/src/document/typst_session.dart';
import 'package:typstrx/src/document/typst_tooltip.dart';
import 'package:typstrx/src/rust/api/session.dart' as rust;
import 'package:typstrx/src/rust/api/types.dart' as rust;

/// A fake bridge session so scheduler behavior is testable without the
/// native library.
class FakeRustSession implements rust.TypstSession {
  final compiledSources = <String>[];
  var generation = 0;

  /// Compilations block until [finishCompile] is called when set.
  Completer<void>? gate;

  var nextCompileSucceeds = true;
  List<rust.TypstDiagnostic> nextDiagnostics = const [];

  @override
  Future<rust.CompileResult> compile({required String source}) async {
    compiledSources.add(source);
    if (gate != null) await gate!.future;
    if (!nextCompileSucceeds) {
      return rust.CompileResult(
        generation: BigInt.from(generation),
        success: false,
        pages: const [],
        diagnostics: nextDiagnostics,
        elapsedMs: BigInt.zero,
      );
    }
    generation++;
    return rust.CompileResult(
      generation: BigInt.from(generation),
      success: true,
      pages: [const rust.PageInfo(widthPt: 595, heightPt: 842)],
      diagnostics: nextDiagnostics,
      elapsedMs: BigInt.zero,
    );
  }

  /// What `completions`/`hover` report as their analysis generation —
  /// settable so tests can simulate it lagging behind [generation].
  var analysisGeneration = 0;
  List<rust.TypstCompletion> completionsToReturn = const [];
  int applyFromUtf16ToReturn = 0;
  rust.TypstTooltip? tooltipToReturn;
  int? lastCompletionCursor;
  int? lastHoverCursor;
  int? lastFunctionInfoCursor;

  @override
  Future<rust.CompletionResult> completions({
    required int cursorUtf16,
    required bool explicit,
  }) async {
    lastCompletionCursor = cursorUtf16;
    return rust.CompletionResult(
      generation: BigInt.from(analysisGeneration),
      applyFromUtf16: applyFromUtf16ToReturn,
      completions: completionsToReturn,
    );
  }

  @override
  Future<rust.HoverResult> hover({required int cursorUtf16}) async {
    lastHoverCursor = cursorUtf16;
    return rust.HoverResult(
      generation: BigInt.from(analysisGeneration),
      tooltip: tooltipToReturn,
    );
  }

  @override
  Future<rust.FunctionInfoResult> functionInfo({
    required int cursorUtf16,
    required String label,
  }) async {
    lastFunctionInfoCursor = cursorUtf16;
    return rust.FunctionInfoResult(
      generation: BigInt.from(analysisGeneration),
      info: null,
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

  int? lastExportGeneration;
  bool? lastExportTagged;

  @override
  Future<Uint8List> exportPdf({
    required BigInt generation,
    required bool tagged,
  }) async {
    lastExportGeneration = generation.toInt();
    lastExportTagged = tagged;
    if (generation.toInt() != this.generation) {
      throw const rust.TypstrxError.stale();
    }
    return Uint8List.fromList('%PDF-fake'.codeUnits);
  }

  final foldingRangesRequestedFor = <String>[];
  List<rust.TypstFoldingRange> foldingRangesToReturn = const [];

  @override
  Future<List<rust.TypstFoldingRange>> foldingRanges({
    required String source,
  }) async {
    foldingRangesRequestedFor.add(source);
    return foldingRangesToReturn;
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

  test('document exports its exact compilation generation as PDF', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    final result = await session.compile('hello');

    final pdf = await result.document!.exportPdf();

    expect(String.fromCharCodes(pdf), '%PDF-fake');
    expect(fake.lastExportGeneration, result.generation);
    expect(fake.lastExportTagged, isTrue);
  });

  test('document exportPdf forwards tagged: false', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    final result = await session.compile('hello');

    await result.document!.exportPdf(tagged: false);

    expect(fake.lastExportTagged, isFalse);
  });

  test(
    'compileFragment wraps layout and maps analysis back to user source',
    () async {
      final fake = FakeRustSession();
      final session = makeSession(fake);
      const source = '#rect(width: 10pt)';
      fake.nextDiagnostics = const [
        rust.TypstDiagnostic(
          severity: rust.DiagnosticSeverity.warning,
          message: 'test warning',
          hints: [],
          utf16Start: 80,
          utf16End: 84,
          line: 3,
          column: 2,
        ),
      ];

      final result = await session.compileFragment(
        source,
        const TypstFragmentOptions(width: 420, margin: 12),
      );
      final compiled = fake.compiledSources.single;
      final prefixLength = compiled.length - source.length;
      expect(
        compiled,
        startsWith(
          '#set page(width: 420pt, height: auto, margin: 12pt, fill: none)\n',
        ),
      );
      expect(compiled, endsWith(source));
      expect(session.lastCompiledSource, source);
      expect(result.diagnostics.single.sourceStart, 80 - prefixLength);
      expect(result.diagnostics.single.line, 2);

      fake.applyFromUtf16ToReturn = prefixLength + 2;
      await session.completions(5);
      await session.hover(6);
      await session.functionInfo(7, 'rect');
      expect(fake.lastCompletionCursor, prefixLength + 5);
      expect(fake.lastHoverCursor, prefixLength + 6);
      expect(fake.lastFunctionInfoCursor, prefixLength + 7);
      expect((await session.completions(5)).applyFromUtf16, 2);
    },
  );

  test('updateSource debounces rapid edits into one compile', () async {
    final fake = FakeRustSession();
    final session = makeSession(
      fake,
      debounce: const Duration(milliseconds: 20),
    );
    session.updateSource('a');
    session.updateSource('ab');
    session.updateSource('abc');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fake.compiledSources, ['abc']);
  });

  test(
    'updateSource coalesces edits arriving during a running compile',
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
    },
  );

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
    final session = makeSession(
      fake,
      debounce: const Duration(milliseconds: 20),
    );
    session.updateSource('pending');
    await session.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fake.compiledSources, isEmpty);
    expect(fake.isDisposed, isTrue);
    expect(() => session.compile('x'), throwsStateError);
  });

  test(
    'lastCompiledSource tracks the most recent compile call, including failures',
    () async {
      final fake = FakeRustSession();
      final session = makeSession(fake);
      expect(session.lastCompiledSource, isNull);

      await session.compile('good');
      expect(session.lastCompiledSource, 'good');

      fake.nextCompileSucceeds = false;
      await session.compile('broken(');
      expect(
        session.lastCompiledSource,
        'broken(',
        reason: 'the native side registers the source regardless of success',
      );
    },
  );

  test(
    'completions converts kinds, including the data-carrying Symbol variant',
    () async {
      final fake = FakeRustSession();
      final session = makeSession(fake);
      fake.analysisGeneration = 3;
      fake.applyFromUtf16ToReturn = 5;
      fake.completionsToReturn = const [
        rust.TypstCompletion(
          kind: rust.TypstCompletionKind.func(),
          label: 'lorem',
          apply: 'lorem(\${})',
          detail: 'Lorem ipsum text.',
        ),
        rust.TypstCompletion(
          kind: rust.TypstCompletionKind.symbol(notation: 'alpha'),
          label: 'alpha',
          apply: 'alpha',
        ),
      ];

      final result = await session.completions(10);
      expect(result.generation, 3);
      expect(result.applyFromUtf16, 5);
      expect(result.completions, hasLength(2));
      expect(result.completions[0].kind.tag, TypstCompletionKindTag.func);
      expect(result.completions[0].kind.notation, isNull);
      expect(result.completions[0].detail, 'Lorem ipsum text.');
      expect(result.completions[1].kind.tag, TypstCompletionKindTag.symbol);
      expect(result.completions[1].kind.notation, 'alpha');
    },
  );

  test('hover converts Text/Code tooltips and null', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);

    fake.tooltipToReturn = const rust.TypstTooltip.text(content: 'A box.');
    var result = await session.hover(1);
    expect(result.tooltip?.kind, TypstTooltipKind.text);
    expect(result.tooltip?.content, 'A box.');

    fake.tooltipToReturn = const rust.TypstTooltip.code(content: '3');
    result = await session.hover(1);
    expect(result.tooltip?.kind, TypstTooltipKind.code);
    expect(result.tooltip?.content, '3');

    fake.tooltipToReturn = null;
    result = await session.hover(1);
    expect(result.tooltip, isNull);
  });

  test(
    'foldingRanges converts kinds and is analyzed against the passed-in source directly',
    () async {
      final fake = FakeRustSession();
      final session = makeSession(fake);
      fake.foldingRangesToReturn = const [
        rust.TypstFoldingRange(
          startUtf16: 1,
          endUtf16: 20,
          kind: rust.TypstFoldingKind.codeBlock,
        ),
        rust.TypstFoldingRange(
          startUtf16: 25,
          endUtf16: 40,
          kind: rust.TypstFoldingKind.comment,
        ),
      ];

      final ranges = await session.foldingRanges('#{ ... }');

      // Unlike completions/hover, this takes the caller's own text — not
      // whatever the native side last compiled — so no session.compile() is
      // needed first, and the fake sees exactly what was passed.
      expect(fake.foldingRangesRequestedFor, ['#{ ... }']);
      expect(ranges, hasLength(2));
      expect(ranges[0].startUtf16, 1);
      expect(ranges[0].endUtf16, 20);
      expect(ranges[0].kind, TypstFoldingKind.codeBlock);
      expect(ranges[1].kind, TypstFoldingKind.comment);
    },
  );
}
