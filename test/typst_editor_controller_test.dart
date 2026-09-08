import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typstrx/src/document/typst_session.dart';
import 'package:typstrx/src/rust/api/session.dart' as rust;
import 'package:typstrx/src/rust/api/types.dart' as rust;
import 'package:typstrx/src/widgets/editor/typst_editor_controller.dart';

/// A fake bridge session so the controller's async scheduling and span
/// building are testable without the native library. `highlight` returns a
/// tree tagging the whole source as a heading, which is enough to assert on
/// without depending on the real Typst grammar.
class FakeRustSession implements rust.TypstSession {
  final highlightedSources = <String>[];
  Completer<void>? highlightGate;

  var compileGeneration = 0;
  List<rust.TypstDiagnostic> diagnosticsToReturn = const [];

  @override
  Future<rust.HighlightNode> highlight({required String source}) async {
    highlightedSources.add(source);
    if (highlightGate != null) await highlightGate!.future;
    return rust.HighlightNode(
      tag: null,
      text: '',
      children: [rust.HighlightNode(tag: rust.HighlightTag.heading, text: source, children: const [])],
    );
  }

  @override
  Future<rust.CompileResult> compile({required String source}) async {
    compileGeneration++;
    return rust.CompileResult(
      generation: BigInt.from(compileGeneration),
      success: true,
      pages: const [rust.PageInfo(widthPt: 595, heightPt: 842)],
      diagnostics: diagnosticsToReturn,
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
    throw UnimplementedError();
  }

  @override
  Future<rust.PageTextData> pageText({required BigInt generation, required int pageIndex}) async {
    throw UnimplementedError();
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

/// Flattens a TextSpan tree into (text, wavy-decoration-color) leaf pairs,
/// in order, for easy assertion.
List<(String, Color?)> flatten(TextSpan span) {
  final out = <(String, Color?)>[];
  void visit(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) {
        final wavy = s.style?.decorationStyle == TextDecorationStyle.wavy;
        out.add((s.text!, wavy ? s.style?.decorationColor : null));
      }
      s.children?.forEach(visit);
    }
  }

  visit(span);
  return out;
}

TypstSession makeSession(FakeRustSession fake) {
  return TypstSession.forTesting(fake, const TypstSessionOptions());
}

void main() {
  test('highlight is requested for the initial text and applied when ready', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    final controller = TypstEditorController(session: session, text: 'hello');

    expect(fake.highlightedSources, ['hello']);
    expect(controller.debugHasFreshTree, isFalse);

    await Future<void>.delayed(Duration.zero);

    expect(controller.debugHasFreshTree, isTrue);
    expect(flatten(controller.debugBuildSpan()), [('hello', null)]);

    controller.dispose();
    await session.dispose();
  });

  test('assigning text requests a fresh highlight', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    final controller = TypstEditorController(session: session, text: 'a');
    await Future<void>.delayed(Duration.zero);

    controller.text = 'ab';
    expect(fake.highlightedSources, ['a', 'ab']);
    await Future<void>.delayed(Duration.zero);
    expect(controller.debugHasFreshTree, isTrue);

    controller.dispose();
    await session.dispose();
  });

  test('rapid edits while a highlight is in flight coalesce to one more call', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    fake.highlightGate = Completer<void>();

    final controller = TypstEditorController(session: session, text: 'first');
    expect(fake.highlightedSources, ['first']);

    // Both arrive while 'first' is still gated.
    controller.text = 'second';
    controller.text = 'third';
    expect(fake.highlightedSources, ['first'], reason: 'no new call starts until the in-flight one resolves');

    fake.highlightGate!.complete();
    fake.highlightGate = null;
    await Future<void>.delayed(Duration.zero);

    // 'second' was superseded by 'third' before it ever started, exactly
    // like TypstSession's own compile coalescing.
    expect(fake.highlightedSources, ['first', 'third']);
    expect(controller.debugHasFreshTree, isTrue);
    expect(flatten(controller.debugBuildSpan()), [('third', null)]);

    controller.dispose();
    await session.dispose();
  });

  test('a stale in-flight result is discarded, not applied to newer text', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    fake.highlightGate = Completer<void>();

    final controller = TypstEditorController(session: session, text: 'old');
    controller.text = 'new';

    // Let the gated 'old' call resolve while 'new' is already current text.
    fake.highlightGate!.complete();
    fake.highlightGate = null;
    await Future<void>.delayed(Duration.zero);

    // The result for 'old' must not be shown against the now-current 'new'.
    // Either a fresh tree for 'new' has already landed, or none has yet —
    // never a tree whose text mismatches `text`.
    if (controller.debugHasFreshTree) {
      expect(flatten(controller.debugBuildSpan()), [('new', null)]);
    } else {
      expect(controller.debugBuildSpan().toPlainText(), 'new');
    }

    await Future<void>.delayed(Duration.zero);
    expect(controller.debugHasFreshTree, isTrue);
    expect(flatten(controller.debugBuildSpan()), [('new', null)]);

    controller.dispose();
    await session.dispose();
  });

  test('diagnostics from session.results overlay a wavy underline on the covered range', () async {
    final fake = FakeRustSession();
    final session = makeSession(fake);
    final controller = TypstEditorController(session: session, text: 'let x = (');
    await Future<void>.delayed(Duration.zero);

    fake.diagnosticsToReturn = const [
      rust.TypstDiagnostic(
        severity: rust.DiagnosticSeverity.error,
        message: 'unclosed delimiter',
        hints: [],
        utf16Start: 8,
        utf16End: 9,
        line: 1,
        column: 8,
      ),
    ];
    await session.compile(controller.text);
    await Future<void>.delayed(Duration.zero);

    // 'let x = (' with the diagnostic covering index 8..9 (the '(') splits
    // the single leaf into an unstyled prefix and a wavy-underlined '(' in
    // the controller's default error color.
    expect(flatten(controller.debugBuildSpan()), [('let x = ', null), ('(', controller.errorColor)]);

    controller.dispose();
    await session.dispose();
  });
}
