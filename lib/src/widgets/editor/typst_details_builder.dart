import 'package:flutter/material.dart';

import '../../document/typst_completion.dart' show TypstCompletionKindTag;
import '../../document/typst_function_info.dart';
import 'typst_completions_builder.dart';
import 'typst_syntax_theme.dart';

/// Builds the widget shown for a function's details — full signature,
/// description, and example code — next to [TypstCodeEditor]'s completion
/// popup, IntelliSense-style.
///
/// Called only for the currently selected completion, and only when it
/// resolved to a function (see [TypstFunctionInfo]); [TypstCodeEditor]
/// itself decides when a fetch is in flight, stale, or empty and simply
/// doesn't call this until [info] is ready.
///
/// [TypstCodeEditor] owns fetching and positioning (next to the completion
/// popup); a builder controls everything inside that. There is no default —
/// [TypstCodeEditor.detailsBuilder] is null unless a caller opts in, so the
/// panel doesn't appear unbidden next to every completion. Pass
/// [defaultTypstDetailsBuilder] to opt into a ready-made look.
typedef TypstDetailsBuilder = Widget Function(BuildContext context, TypstFunctionInfo info);

/// A reasonable default rendering of [TypstFunctionInfo]: the signature in a
/// monospace heading (colored per token — see [TypstSignatureTokenKind] —
/// the same way [typstCompletionKindColor] colors the completion list), the
/// description underneath, and (when present) the example in a syntax-
/// colored code block, using [TypstSyntaxTheme.defaultTheme].
Widget defaultTypstDetailsBuilder(BuildContext context, TypstFunctionInfo info) {
  final colorScheme = Theme.of(context).colorScheme;
  const signatureStyle = TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13);
  const exampleStyle = TextStyle(fontFamily: 'monospace', fontSize: 11);
  return Material(
    color: colorScheme.surfaceContainerHigh,
    elevation: 4,
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(_signatureSpan(info.signature, signatureStyle)),
            if (info.description case final description?) ...[
              const SizedBox(height: 8),
              Text(description, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            ],
            if (info.example case final example?) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text.rich(
                  info.exampleHighlight != null
                      ? typstHighlightedSpan(
                          info.exampleHighlight!,
                          TypstSyntaxTheme.defaultTheme,
                          style: exampleStyle,
                        )
                      : TextSpan(text: example, style: exampleStyle),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

TextSpan _signatureSpan(List<TypstSignatureToken> tokens, TextStyle base) {
  return TextSpan(
    style: base,
    children: [
      for (final token in tokens)
        TextSpan(text: token.text, style: TextStyle(color: _signatureTokenColor(token.kind))),
    ],
  );
}

Color _signatureTokenColor(TypstSignatureTokenKind kind) {
  return switch (kind) {
    TypstSignatureTokenKind.name => typstCompletionKindColor(TypstCompletionKindTag.func),
    TypstSignatureTokenKind.param => typstCompletionKindColor(TypstCompletionKindTag.param),
    TypstSignatureTokenKind.punctuation => typstCompletionKindColor(TypstCompletionKindTag.syntax),
  };
}
