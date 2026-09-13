import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../rust/api/session.dart' as rust;
import '../rust/api/types.dart' as rust;
import 'typst_completion.dart';
import 'typst_diagnostic.dart';
import 'typst_document.dart';
import 'typst_folding_range.dart';
import 'typst_function_info.dart';
import 'typst_highlight.dart';
import 'typst_tooltip.dart';

/// Configuration for [TypstSession.create].
class TypstSessionOptions {
  const TypstSessionOptions({
    this.packageCacheDir,
    this.allowPackageDownload = true,
    this.compileDebounce = const Duration(milliseconds: 250),
  });

  /// Directory where downloaded `@preview` packages are cached. When null,
  /// the platform's standard Typst cache directory is used; on mobile
  /// platforms pass an app-specific directory (e.g. from `path_provider`).
  final String? packageCacheDir;

  /// Whether `@preview` packages may be downloaded from the network. Cached
  /// packages keep working when false.
  final bool allowPackageDownload;

  /// How long [TypstSession.updateSource] waits after the last edit before
  /// compiling.
  final Duration compileDebounce;
}

/// Page constraints used when compiling Typst as an embedded fragment.
///
/// The generated preamble makes the page exactly [width] points wide, lets
/// its height follow the content, and removes the page fill by default. A
/// `#set page(...)` rule in [source] comes later and can deliberately
/// override any of these defaults.
class TypstFragmentOptions {
  const TypstFragmentOptions({
    required this.width,
    this.margin = 0,
    this.transparent = true,
  });

  final double width;
  final double margin;
  final bool transparent;

  String _preamble() {
    if (!width.isFinite || width <= 0) {
      throw ArgumentError.value(width, 'width', 'must be finite and positive');
    }
    if (!margin.isFinite || margin < 0) {
      throw ArgumentError.value(
        margin,
        'margin',
        'must be finite and non-negative',
      );
    }
    final fill = transparent ? ', fill: none' : '';
    return '#set page(width: ${_number(width)}pt, height: auto, '
        'margin: ${_number(margin)}pt$fill)\n';
  }

  static String _number(double value) => value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();
}

class _CompileRequest {
  const _CompileRequest(
    this.userSource,
    this.compiledSource,
    this.prefixLength,
    this.prefixLines,
  );

  final String userSource;
  final String compiledSource;
  final int prefixLength;
  final int prefixLines;

  factory _CompileRequest.document(String source) =>
      _CompileRequest(source, source, 0, 0);

  factory _CompileRequest.fragment(
    String source,
    TypstFragmentOptions options,
  ) {
    final prefix = options._preamble();
    return _CompileRequest(
      source,
      '$prefix$source',
      prefix.length,
      '\n'.allMatches(prefix).length,
    );
  }
}

/// The result of a compilation.
class TypstCompileResult {
  const TypstCompileResult({
    required this.document,
    required this.diagnostics,
    required this.generation,
    required this.elapsed,
  });

  /// The compiled document, or null if compilation failed. On failure the
  /// session's previous [TypstSession.document] stays available.
  final TypstDocument? document;

  /// Errors and warnings emitted by the compiler.
  final List<TypstDiagnostic> diagnostics;

  /// The generation of [document], or of the last successful compilation if
  /// this one failed (0 if none).
  final int generation;

  /// Wall-clock compilation time.
  final Duration elapsed;

  /// Whether a document was produced.
  bool get success => document != null;
}

/// A Typst compilation session.
///
/// Holds the native compiler state (fonts, package cache, incremental
/// compilation caches) across compilations. Use [updateSource] for live
/// editing (debounced and coalesced) or [compile] for one-off compilations.
class TypstSession {
  TypstSession._(this._native, this._options);

  /// Injects a custom bridge session — for tests only.
  @visibleForTesting
  TypstSession.forTesting(rust.TypstSession native, TypstSessionOptions options)
    : this._(native, options);

  final rust.TypstSession _native;
  final TypstSessionOptions _options;

  final _results = StreamController<TypstCompileResult>.broadcast();
  final _documents = StreamController<TypstDocument>.broadcast();

  TypstDocument? _document;
  bool _disposed = false;
  String? _lastCompiledSource;

  /// Serializes native compile calls.
  Future<void> _lock = Future.value();

  Timer? _debounce;
  _CompileRequest? _pendingRequest;
  bool _drainScheduled = false;
  int _analysisPrefixLength = 0;

  /// Creates a new session with the embedded default fonts.
  static Future<TypstSession> create({
    TypstSessionOptions options = const TypstSessionOptions(),
  }) async {
    final native = await rust.TypstSession.create(
      options: rust.SessionOptions(
        packageCacheDir: options.packageCacheDir,
        allowPackageDownload: options.allowPackageDownload,
      ),
    );
    return TypstSession._(native, options);
  }

  /// The latest successfully compiled document, if any.
  TypstDocument? get document => _document;

  /// The exact source text used for the most recent [compile] call
  /// (successful or not) — null before the first one.
  ///
  /// [completions] and [hover] analyze this text, not necessarily whatever
  /// is in a caller's live buffer right now: value-aware analysis (field
  /// access completions, "show computed value" hover) needs the compiler's
  /// own internal state, which only reflects an edit once it has gone
  /// through [compile]. Compare this against the buffer's current text
  /// before applying a [TypstCompletionResult]/[TypstHoverResult] — if they
  /// differ, the buffer has moved on since the analysis ran and the result
  /// should be discarded rather than applied at the wrong position.
  String? get lastCompiledSource => _lastCompiledSource;

  /// Every compilation result, including failed ones (with diagnostics).
  Stream<TypstCompileResult> get results => _results.stream;

  /// Successfully compiled documents only.
  Stream<TypstDocument> get documents => _documents.stream;

  /// Schedules a compilation of [source].
  ///
  /// Debounced by [TypstSessionOptions.compileDebounce] and coalesced: while
  /// a compilation is running at most one more is queued, always with the
  /// most recent source. Results are delivered on [results]/[documents].
  void updateSource(String source) {
    _update(_CompileRequest.document(source));
  }

  /// Schedules an embedded-fragment compilation of [source].
  void updateFragmentSource(String source, TypstFragmentOptions options) {
    _update(_CompileRequest.fragment(source, options));
  }

  void _update(_CompileRequest request) {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(_options.compileDebounce, () {
      _pendingRequest = request;
      _scheduleDrain();
    });
  }

  /// Compiles [source] immediately (still serialized with other compiles)
  /// and returns the result. Also emits on [results]/[documents].
  Future<TypstCompileResult> compile(String source) {
    _checkDisposed();
    return _serialized(() => _compileNow(_CompileRequest.document(source)));
  }

  /// Compiles [source] as a content-sized embedded page.
  ///
  /// Diagnostics and editor analysis offsets are mapped back to [source], so
  /// callers never need to account for typstrx's generated page preamble.
  Future<TypstCompileResult> compileFragment(
    String source,
    TypstFragmentOptions options,
  ) {
    _checkDisposed();
    return _serialized(
      () => _compileNow(_CompileRequest.fragment(source, options)),
    );
  }

  /// Computes a syntax-highlighting tree for [source].
  ///
  /// Independent of [compile]/[updateSource]: this only parses, so it never
  /// contends with an in-flight compile or render and is safe to call on
  /// every keystroke.
  Future<TypstHighlightNode> highlight(String source) async {
    _checkDisposed();
    return TypstHighlightNode.fromRust(await _native.highlight(source: source));
  }

  /// Computes folding ranges for [source] — collapsible regions like code
  /// blocks, content blocks, argument lists, and array/dict literals that
  /// span more than one line. Headings are not included; see the Rust
  /// `folding` module for why.
  ///
  /// Independent of [compile]/[updateSource], like [highlight]: this only
  /// parses, so it's safe to call on every keystroke. Unlike [completions]/
  /// [hover], there is no [lastCompiledSource] staleness to check — the
  /// result is computed directly from [source], not the compiler's own
  /// registered one, so it's already current for whatever the caller
  /// passes.
  Future<List<TypstFoldingRange>> foldingRanges(String source) async {
    _checkDisposed();
    return [
      for (final r in await _native.foldingRanges(source: source))
        TypstFoldingRange.fromRust(r),
    ];
  }

  /// Computes completions at [cursorUtf16] in [lastCompiledSource].
  ///
  /// See [lastCompiledSource] for why this doesn't take a `source`
  /// parameter, and what a caller must check before using the result.
  Future<TypstCompletionResult> completions(
    int cursorUtf16, {
    bool explicit = false,
  }) async {
    _checkDisposed();
    final prefixLength = _analysisPrefixLength;
    final result = TypstCompletionResult.fromRust(
      await _native.completions(
        cursorUtf16: cursorUtf16 + prefixLength,
        explicit: explicit,
      ),
    );
    // Only a fragment compilation's applyFromUtf16 needs mapping back to
    // the caller's own source — same guard _mapDiagnostic uses, and for
    // the same reason: skip touching an offset (here, a subtract-then-
    // clamp) that has nothing to correct for on the plain-compile path,
    // rather than relying on prefixLength being 0 to make it a no-op.
    if (prefixLength == 0) return result;
    return TypstCompletionResult(
      generation: result.generation,
      applyFromUtf16: (result.applyFromUtf16 - prefixLength).clamp(
        0,
        cursorUtf16,
      ),
      completions: result.completions,
    );
  }

  /// Computes a hover tooltip at [cursorUtf16] in [lastCompiledSource]. See
  /// [lastCompiledSource] for what a caller must check before using it.
  ///
  /// Unlike [completions], nothing in [TypstHoverResult] carries a source
  /// offset that a fragment's prefix could throw off, so — besides adding
  /// the prefix to [cursorUtf16] itself, safe at any prefix length,
  /// including zero — there's no output to guard the way [completions]
  /// guards `applyFromUtf16` (see [_mapDiagnostic] for the same reasoning
  /// applied to diagnostics).
  Future<TypstHoverResult> hover(int cursorUtf16) async {
    _checkDisposed();
    return TypstHoverResult.fromRust(
      await _native.hover(cursorUtf16: cursorUtf16 + _analysisPrefixLength),
    );
  }

  /// Looks up documentation for the function named [label], for an
  /// IntelliSense-style details panel shown alongside the completion list.
  ///
  /// [cursorUtf16] is used first to resolve whatever's actually at that
  /// position in [lastCompiledSource] (handles field access like
  /// `calc.abs`, local functions, etc.); if that doesn't resolve to a
  /// function, falls back to a plain lookup of [label] in the global scope
  /// (handles browsing completions before a full expression exists, e.g.
  /// `#re|`). See [lastCompiledSource] for what a caller must check before
  /// using the result.
  ///
  /// Like [hover], [TypstFunctionInfoResult] carries no source offset a
  /// fragment's prefix could throw off, so there's nothing on the output
  /// side to guard against a nonzero prefix — see the note on [hover].
  Future<TypstFunctionInfoResult> functionInfo(
    int cursorUtf16,
    String label,
  ) async {
    _checkDisposed();
    return TypstFunctionInfoResult.fromRust(
      await _native.functionInfo(
        cursorUtf16: cursorUtf16 + _analysisPrefixLength,
        label: label,
      ),
    );
  }

  /// Registers all font faces in [data] (TTF/OTF, also collections) for
  /// subsequent compilations. Returns the number of faces added.
  Future<int> registerFont(Uint8List data) {
    _checkDisposed();
    return _native.registerFont(data: data);
  }

  /// Adds or replaces an in-memory project file (image, module, data file)
  /// that Typst source can reference by [path], e.g. `/images/logo.png`.
  Future<void> setFile(String path, Uint8List data) {
    _checkDisposed();
    return _native.setFile(path: path, data: data);
  }

  /// Renders a page region; used by [TypstPage.render].
  @internal
  Future<rust.RenderedRegion> renderPageRegion({
    required int generation,
    required int pageIndex,
    required int x,
    required int y,
    required int width,
    required int height,
    required int fullWidth,
    required int fullHeight,
    required int backgroundArgb,
  }) {
    _checkDisposed();
    return _native.renderPageRegion(
      generation: BigInt.from(generation),
      pageIndex: pageIndex,
      x: x,
      y: y,
      width: width,
      height: height,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      backgroundArgb: backgroundArgb,
    );
  }

  /// Extracts text/link geometry for a page; used by [TypstPage].
  @internal
  Future<rust.PageTextData> pageText({
    required int generation,
    required int pageIndex,
  }) {
    _checkDisposed();
    return _native.pageText(
      generation: BigInt.from(generation),
      pageIndex: pageIndex,
    );
  }

  /// Exports the compiled document identified by [generation] as vector PDF.
  @internal
  Future<Uint8List> exportPdf({required int generation}) {
    _checkDisposed();
    return _native.exportPdf(generation: BigInt.from(generation));
  }

  /// Releases the native session. Streams close and further calls throw.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    _pendingRequest = null;
    // Wait for an in-flight compile before dropping the native handle.
    await _lock;
    _native.dispose();
    await _results.close();
    await _documents.close();
  }

  void _scheduleDrain() {
    if (_drainScheduled || _disposed) return;
    _drainScheduled = true;
    _serialized(() async {
      _drainScheduled = false;
      final request = _pendingRequest;
      _pendingRequest = null;
      if (request == null || _disposed) return;
      await _compileNow(request);
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<TypstCompileResult> _compileNow(_CompileRequest request) async {
    final raw = await _native.compile(source: request.compiledSource);
    // Unconditional: the native side registers `source` as the compiler's
    // main file regardless of whether compilation succeeded, which is
    // exactly what completions/hover analyze — see `lastCompiledSource`.
    _lastCompiledSource = request.userSource;
    _analysisPrefixLength = request.prefixLength;
    final result = TypstCompileResult(
      document: raw.success
          ? TypstDocument(
              session: this,
              generation: raw.generation.toInt(),
              pageSizes: [
                for (final page in raw.pages)
                  (width: page.widthPt, height: page.heightPt),
              ],
            )
          : null,
      diagnostics: [
        for (final diagnostic in raw.diagnostics)
          _mapDiagnostic(TypstDiagnostic.fromRust(diagnostic), request),
      ],
      generation: raw.generation.toInt(),
      elapsed: Duration(milliseconds: raw.elapsedMs.toInt()),
    );
    if (_disposed) return result;
    if (result.document != null) {
      _document = result.document;
      _documents.add(result.document!);
    }
    _results.add(result);
    return result;
  }

  static TypstDiagnostic _mapDiagnostic(
    TypstDiagnostic diagnostic,
    _CompileRequest request,
  ) {
    if (request.prefixLength == 0 || diagnostic.sourceStart == null) {
      return diagnostic;
    }
    final start = diagnostic.sourceStart! - request.prefixLength;
    final end = diagnostic.sourceEnd == null
        ? null
        : diagnostic.sourceEnd! - request.prefixLength;
    if (start < 0 || (end != null && end < 0)) {
      return TypstDiagnostic(
        severity: diagnostic.severity,
        message: diagnostic.message,
        hints: diagnostic.hints,
      );
    }
    return TypstDiagnostic(
      severity: diagnostic.severity,
      message: diagnostic.message,
      hints: diagnostic.hints,
      sourceStart: start,
      sourceEnd: end,
      line: diagnostic.line == null
          ? null
          : diagnostic.line! - request.prefixLines,
      column: diagnostic.column,
    );
  }

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('TypstSession has been disposed');
    }
  }
}
