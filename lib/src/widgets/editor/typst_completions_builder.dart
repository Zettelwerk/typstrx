import 'package:flutter/material.dart';

import '../../document/typst_completion.dart';

/// Builds the widget shown for a set of completion candidates in
/// [TypstCodeEditor]'s popup.
///
/// [completions] is never empty when this is called. [selectedIndex] is the
/// keyboard-navigable selection (arrow keys move it, enter/tab apply it) —
/// mark it distinctly so keyboard users can see where they are. Call
/// [onSelected] when the user picks an item, by tap or otherwise; the editor
/// handles applying it to the buffer and closing the popup.
///
/// [TypstCodeEditor] owns the popup's position (anchored under the caret)
/// and dismissal (escape, tapping outside); a builder controls everything
/// inside that: container chrome, row layout, scrolling.
///
/// [defaultTypstCompletionsBuilder] is [TypstCodeEditor]'s default. Write a
/// custom builder to change the popup's look entirely, or reuse
/// [typstCompletionKindIcon]/[typstCompletionKindColor] to keep its
/// kind-to-icon mapping while changing everything else.
typedef TypstCompletionsBuilder =
    Widget Function(
      BuildContext context,
      List<TypstCompletion> completions,
      int selectedIndex,
      ValueChanged<TypstCompletion> onSelected,
    );

/// A representative icon for [tag], loosely following the convention common
/// to other editors' completion lists (VS Code among them).
IconData typstCompletionKindIcon(TypstCompletionKindTag tag) {
  return switch (tag) {
    TypstCompletionKindTag.syntax => Icons.code,
    TypstCompletionKindTag.func => Icons.functions,
    TypstCompletionKindTag.type => Icons.category_outlined,
    TypstCompletionKindTag.param => Icons.input,
    TypstCompletionKindTag.constant => Icons.push_pin_outlined,
    TypstCompletionKindTag.path => Icons.insert_drive_file_outlined,
    TypstCompletionKindTag.package => Icons.inventory_2_outlined,
    TypstCompletionKindTag.label => Icons.label_outline,
    TypstCompletionKindTag.font => Icons.text_fields,
    TypstCompletionKindTag.symbol => Icons.emoji_symbols_outlined,
  };
}

/// An accent color for [tag], paired with [typstCompletionKindIcon].
///
/// Fixed rather than [Theme]-derived — like most editors' kind colors, this
/// is a small identifying palette chosen to read clearly on both light and
/// dark container backgrounds, not one meant to shift with the app's theme.
Color typstCompletionKindColor(TypstCompletionKindTag tag) {
  return switch (tag) {
    TypstCompletionKindTag.syntax => const Color(0xFF78909C),
    TypstCompletionKindTag.func => const Color(0xFF9C27B0),
    TypstCompletionKindTag.type => const Color(0xFF00897B),
    TypstCompletionKindTag.param => const Color(0xFF1E88E5),
    TypstCompletionKindTag.constant => const Color(0xFFEF6C00),
    TypstCompletionKindTag.path => const Color(0xFF6D4C41),
    TypstCompletionKindTag.package => const Color(0xFF43A047),
    TypstCompletionKindTag.label => const Color(0xFF3F51B5),
    TypstCompletionKindTag.font => const Color(0xFFD81B60),
    TypstCompletionKindTag.symbol => const Color(0xFF673AB7),
  };
}

/// [TypstCodeEditor]'s default [TypstCompletionsBuilder]: a Material 3
/// surface (theme-aware, so it holds up in dark mode) with a kind icon,
/// monospace label, and muted detail text per row, scrollable when the list
/// overflows [maxHeight].
Widget defaultTypstCompletionsBuilder(
  BuildContext context,
  List<TypstCompletion> completions,
  int selectedIndex,
  ValueChanged<TypstCompletion> onSelected,
) {
  final colorScheme = Theme.of(context).colorScheme;
  return Material(
    color: colorScheme.surfaceContainerHigh,
    elevation: 4,
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 200),
      child: Scrollbar(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: completions.length,
          itemBuilder: (context, index) {
            final item = completions[index];
            final selected = index == selectedIndex;
            return Material(
              color: selected ? colorScheme.primaryContainer : Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Icon(typstCompletionKindIcon(item.kind.tag), size: 16, color: typstCompletionKindColor(item.kind.tag)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                      ),
                      // A long one-sentence detail must stay bounded: unlike
                      // a Row's other children, Text has no intrinsic width
                      // cap, and this row (unlike ListTile) provides none
                      // for its trailing slot on its own.
                      if (item.detail != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 96),
                            child: Text(
                              item.detail!,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
