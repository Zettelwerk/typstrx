import '../rust/api/types.dart' as rust;

/// Severity of a [TypstDiagnostic].
enum TypstDiagnosticSeverity { error, warning }

/// A compiler error or warning.
class TypstDiagnostic {
  const TypstDiagnostic({
    required this.severity,
    required this.message,
    required this.hints,
    this.sourceStart,
    this.sourceEnd,
    this.line,
    this.column,
  });

  /// Whether this is an error or a warning.
  final TypstDiagnosticSeverity severity;

  /// The diagnostic message.
  final String message;

  /// Additional hints on how to resolve the problem.
  final List<String> hints;

  /// Start offset into the main source, in UTF-16 code units (directly usable
  /// as a Dart [String] index). Null when the diagnostic does not point into
  /// the main source (e.g. errors inside packages).
  final int? sourceStart;

  /// End offset into the main source, in UTF-16 code units.
  final int? sourceEnd;

  /// 1-based line of [sourceStart].
  final int? line;

  /// 0-based column of [sourceStart] within [line], in UTF-16 code units.
  final int? column;

  @override
  String toString() {
    final pos = line != null ? '$line:${column ?? 0}: ' : '';
    return '$pos${severity.name}: $message';
  }

  /// Converts a bridge-level diagnostic.
  static TypstDiagnostic fromRust(rust.TypstDiagnostic diagnostic) {
    return TypstDiagnostic(
      severity: switch (diagnostic.severity) {
        rust.DiagnosticSeverity.error => TypstDiagnosticSeverity.error,
        rust.DiagnosticSeverity.warning => TypstDiagnosticSeverity.warning,
      },
      message: diagnostic.message,
      hints: diagnostic.hints,
      sourceStart: diagnostic.utf16Start,
      sourceEnd: diagnostic.utf16End,
      line: diagnostic.line,
      column: diagnostic.column,
    );
  }
}
