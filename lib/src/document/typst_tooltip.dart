import '../rust/api/types.dart' as rust;

/// Whether a [TypstTooltip]'s content is prose or Typst code.
enum TypstTooltipKind { text, code }

/// A hover tooltip.
class TypstTooltip {
  const TypstTooltip({required this.kind, required this.content});

  final TypstTooltipKind kind;

  /// Plain prose when [kind] is [TypstTooltipKind.text]; a snippet of Typst
  /// code (e.g. a function call showing its resolved arguments) when
  /// [kind] is [TypstTooltipKind.code] — callers may want to render that
  /// case in a monospace/code style.
  final String content;

  static TypstTooltip fromRust(rust.TypstTooltip tooltip) {
    return switch (tooltip) {
      rust.TypstTooltip_Text(:final content) => TypstTooltip(
        kind: TypstTooltipKind.text,
        content: content,
      ),
      rust.TypstTooltip_Code(:final content) => TypstTooltip(
        kind: TypstTooltipKind.code,
        content: content,
      ),
    };
  }
}

/// The result of [TypstSession.hover]. See [TypstCompletionResult] for what
/// [generation] means and why [TypstSession.lastCompiledSource] is what
/// actually determines whether [tooltip] applies to the caller's current
/// buffer.
class TypstHoverResult {
  const TypstHoverResult({required this.generation, this.tooltip});

  final int generation;
  final TypstTooltip? tooltip;

  static TypstHoverResult fromRust(rust.HoverResult result) {
    return TypstHoverResult(
      generation: result.generation.toInt(),
      tooltip: result.tooltip != null
          ? TypstTooltip.fromRust(result.tooltip!)
          : null,
    );
  }
}
