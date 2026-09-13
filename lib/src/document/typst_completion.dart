import '../rust/api/types.dart' as rust;

/// Which category a [TypstCompletion] belongs to.
enum TypstCompletionKindTag {
  syntax,
  func,
  type,
  param,
  constant,
  path,
  package,
  label,
  font,
  symbol,
}

/// The kind of item a [TypstCompletion] completes to.
///
/// [notation] is only set when [tag] is [TypstCompletionKindTag.symbol] — the
/// symbol's literal shorthand/name, not user-facing text.
class TypstCompletionKind {
  const TypstCompletionKind._(this.tag, this.notation);

  final TypstCompletionKindTag tag;
  final String? notation;

  static TypstCompletionKind fromRust(rust.TypstCompletionKind kind) {
    return switch (kind) {
      rust.TypstCompletionKind_Syntax() => const TypstCompletionKind._(
        TypstCompletionKindTag.syntax,
        null,
      ),
      rust.TypstCompletionKind_Func() => const TypstCompletionKind._(
        TypstCompletionKindTag.func,
        null,
      ),
      rust.TypstCompletionKind_Type() => const TypstCompletionKind._(
        TypstCompletionKindTag.type,
        null,
      ),
      rust.TypstCompletionKind_Param() => const TypstCompletionKind._(
        TypstCompletionKindTag.param,
        null,
      ),
      rust.TypstCompletionKind_Constant() => const TypstCompletionKind._(
        TypstCompletionKindTag.constant,
        null,
      ),
      rust.TypstCompletionKind_Path() => const TypstCompletionKind._(
        TypstCompletionKindTag.path,
        null,
      ),
      rust.TypstCompletionKind_Package() => const TypstCompletionKind._(
        TypstCompletionKindTag.package,
        null,
      ),
      rust.TypstCompletionKind_Label() => const TypstCompletionKind._(
        TypstCompletionKindTag.label,
        null,
      ),
      rust.TypstCompletionKind_Font() => const TypstCompletionKind._(
        TypstCompletionKindTag.font,
        null,
      ),
      rust.TypstCompletionKind_Symbol(:final notation) => TypstCompletionKind._(
        TypstCompletionKindTag.symbol,
        notation,
      ),
    };
  }
}

/// An autocompletion option.
class TypstCompletion {
  const TypstCompletion({
    required this.kind,
    required this.label,
    required this.apply,
    this.detail,
  });

  /// The category this completion belongs to.
  final TypstCompletionKind kind;

  /// The text shown in a completion list — typically more descriptive than
  /// [apply] (e.g. `"let binding"`, not `"let"`), meant to be filtered
  /// against what the user has typed so far.
  final String label;

  /// The text to insert. May contain snippet placeholders like `${name}` or
  /// an empty tab stop `${}` — see the `typst-snippet` placeholder syntax;
  /// there is no numbering, stops are visited in the order they appear.
  final String apply;

  /// An optional one-sentence description.
  final String? detail;

  static TypstCompletion fromRust(rust.TypstCompletion c) {
    return TypstCompletion(
      kind: TypstCompletionKind.fromRust(c.kind),
      label: c.label,
      apply: c.apply,
      detail: c.detail,
    );
  }
}

/// The result of [TypstSession.completions].
///
/// Analyzed against the source as of the last [TypstSession.compile] call
/// (successful or not), **not** necessarily the caller's current buffer —
/// see [TypstSession.lastCompiledSource] for why, and how to guard against
/// applying [applyFromUtf16] to a buffer it wasn't computed for.
class TypstCompletionResult {
  const TypstCompletionResult({
    required this.generation,
    required this.applyFromUtf16,
    required this.completions,
  });

  /// The generation of the document displayed when this analysis ran —
  /// useful for correlating with what's on screen, but *not* sufficient on
  /// its own to know whether [applyFromUtf16] is safe to use: see
  /// [TypstSession.lastCompiledSource].
  final int generation;

  /// Where completions apply from, in UTF-16 code units. Applying one means
  /// replacing the range from this offset to the cursor with the chosen
  /// [TypstCompletion.apply].
  final int applyFromUtf16;

  final List<TypstCompletion> completions;

  static TypstCompletionResult fromRust(rust.CompletionResult result) {
    return TypstCompletionResult(
      generation: result.generation.toInt(),
      applyFromUtf16: result.applyFromUtf16,
      completions: [
        for (final c in result.completions) TypstCompletion.fromRust(c),
      ],
    );
  }
}
