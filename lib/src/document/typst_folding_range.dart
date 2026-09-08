import '../rust/api/types.dart' as rust;

/// What kind of construct a [TypstFoldingRange] spans.
enum TypstFoldingKind { codeBlock, contentBlock, args, array, dict, comment }

/// A collapsible region of Typst source — a code block, content block,
/// array/dict literal, function call's argument list, or block comment. See
/// [TypstSession.foldingRanges].
///
/// Pure syntax: computed directly from whatever source text was passed in,
/// with no dependency on a compiled World. Unlike [TypstCompletionResult]/
/// [TypstHoverResult] there is no generation to check against staleness —
/// call [TypstSession.foldingRanges] again with the current buffer and the
/// result is already current for it.
class TypstFoldingRange {
  const TypstFoldingRange({required this.startUtf16, required this.endUtf16, required this.kind});

  /// Start of the region, in UTF-16 code units — inclusive of the opening
  /// delimiter (e.g. the `{` of a code block).
  final int startUtf16;

  /// End of the region, in UTF-16 code units — inclusive of the closing
  /// delimiter (e.g. the `}` of a code block).
  final int endUtf16;

  final TypstFoldingKind kind;

  static TypstFoldingRange fromRust(rust.TypstFoldingRange range) {
    return TypstFoldingRange(
      startUtf16: range.startUtf16,
      endUtf16: range.endUtf16,
      kind: switch (range.kind) {
        rust.TypstFoldingKind.codeBlock => TypstFoldingKind.codeBlock,
        rust.TypstFoldingKind.contentBlock => TypstFoldingKind.contentBlock,
        rust.TypstFoldingKind.args => TypstFoldingKind.args,
        rust.TypstFoldingKind.array => TypstFoldingKind.array,
        rust.TypstFoldingKind.dict => TypstFoldingKind.dict,
        rust.TypstFoldingKind.comment => TypstFoldingKind.comment,
      },
    );
  }
}
