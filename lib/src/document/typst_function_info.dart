import '../rust/api/types.dart' as rust;

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
  });

  /// The function's name, e.g. `"rect"`.
  final String name;

  /// A synthesized call signature, e.g. `"rect(width?:, height?:, fill?:,
  /// body)"`. Cheap to compute and always present.
  final String signature;

  /// The function's documentation, as Markdown, with the [example] section
  /// removed. Null for functions Typst doesn't carry documentation for.
  final String? description;

  /// Example Typst source demonstrating the function, when its
  /// documentation has one.
  final String? example;

  static TypstFunctionInfo fromRust(rust.TypstFunctionInfo info) {
    return TypstFunctionInfo(
      name: info.name,
      signature: info.signature,
      description: info.description,
      example: info.example,
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
      info: result.info != null ? TypstFunctionInfo.fromRust(result.info!) : null,
    );
  }
}
