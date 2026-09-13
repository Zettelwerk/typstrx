import '../rust/api/types.dart' as rust;
import 'typst_highlight.dart';

/// A piece of a [TypstFunctionInfo.signature], carrying enough structure for
/// a caller to color a function's name differently from its parameter names
/// and punctuation, without having to parse a flat signature string back
/// apart.
enum TypstSignatureTokenKind {
  /// The function's own name.
  name,

  /// A parameter's name.
  param,

  /// Parens, commas, colons, `?`, `..` — everything that isn't a name.
  punctuation,
}

/// One piece of a [TypstFunctionInfo.signature]. See
/// [TypstSignatureTokenKind].
class TypstSignatureToken {
  const TypstSignatureToken({required this.text, required this.kind});

  final String text;
  final TypstSignatureTokenKind kind;

  static TypstSignatureToken fromRust(rust.TypstSignatureToken token) {
    return TypstSignatureToken(
      text: token.text,
      kind: switch (token.kind) {
        rust.TypstSignatureTokenKind.name => TypstSignatureTokenKind.name,
        rust.TypstSignatureTokenKind.param => TypstSignatureTokenKind.param,
        rust.TypstSignatureTokenKind.punctuation =>
          TypstSignatureTokenKind.punctuation,
      },
    );
  }
}

/// Documentation for a function, for an IntelliSense-style details panel
/// shown alongside the completion list.
///
/// Only covers Typst's built-in (native/element) functions — resolving a
/// user-defined closure or a name reached through more than one level of
/// field access (e.g. `a.b.c`) is out of scope, and callers should treat a
/// null [TypstSession.functionInfo] result as "no details available", not an
/// error.
class TypstFunctionInfo {
  const TypstFunctionInfo({
    required this.name,
    required this.signature,
    this.description,
    this.example,
    this.exampleHighlight,
  });

  /// The function's name, e.g. `"rect"`.
  final String name;

  /// A synthesized call signature (e.g. `rect(width?:, height?:, fill?:,
  /// body)`), broken into styleable pieces. Cheap to compute and always
  /// present when this resolved at all.
  final List<TypstSignatureToken> signature;

  /// The function's documentation, as Markdown, with the [example] section
  /// removed. Null for functions Typst doesn't carry documentation for.
  final String? description;

  /// Example Typst source demonstrating the function, when its
  /// documentation has one.
  final String? example;

  /// A syntax-highlighting tree for [example], computed the same way
  /// [TypstSession.highlight] would for it — non-null exactly when [example]
  /// is.
  final TypstHighlightNode? exampleHighlight;

  static TypstFunctionInfo fromRust(rust.TypstFunctionInfo info) {
    return TypstFunctionInfo(
      name: info.name,
      signature: [
        for (final token in info.signature) TypstSignatureToken.fromRust(token),
      ],
      description: info.description,
      example: info.example,
      exampleHighlight: info.exampleHighlight != null
          ? TypstHighlightNode.fromRust(info.exampleHighlight!)
          : null,
    );
  }
}

/// The result of [TypstSession.functionInfo]. See [TypstCompletionResult]
/// for what [generation] means and why [TypstSession.lastCompiledSource] is
/// what actually determines whether [info] applies to the caller's current
/// buffer.
class TypstFunctionInfoResult {
  const TypstFunctionInfoResult({required this.generation, this.info});

  final int generation;
  final TypstFunctionInfo? info;

  static TypstFunctionInfoResult fromRust(rust.FunctionInfoResult result) {
    return TypstFunctionInfoResult(
      generation: result.generation.toInt(),
      info: result.info != null
          ? TypstFunctionInfo.fromRust(result.info!)
          : null,
    );
  }
}
