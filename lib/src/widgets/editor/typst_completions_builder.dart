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
/// surface (theme-aware, so it holds up in dark mode) with a kind icon and
/// monospace label per row. The selected row (see [selectedIndex]) expands
/// to show its full detail text underneath instead of the label-only row
/// other items get — a one-sentence description rarely fits truncated next
/// to a label, so it's shown in full only for the row that's actually
/// relevant right now. Scrollable, with the selection kept in view as
/// [selectedIndex] moves — including wrapping from the last row back to the
/// first, where a plain [Scrollable.ensureVisible] would no-op against a
/// lazily-built [ListView] that hasn't built that row yet.
Widget defaultTypstCompletionsBuilder(
  BuildContext context,
  List<TypstCompletion> completions,
  int selectedIndex,
  ValueChanged<TypstCompletion> onSelected,
) {
  return _CompletionsList(
    completions: completions,
    selectedIndex: selectedIndex,
    onSelected: onSelected,
  );
}

class _CompletionsList extends StatefulWidget {
  const _CompletionsList({
    required this.completions,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<TypstCompletion> completions;
  final int selectedIndex;
  final ValueChanged<TypstCompletion> onSelected;

  @override
  State<_CompletionsList> createState() => _CompletionsListState();
}

class _CompletionsListState extends State<_CompletionsList> {
  final _scrollController = ScrollController();
  final _itemKeys = <GlobalKey>[];

  @override
  void initState() {
    super.initState();
    _syncItemKeys();
  }

  @override
  void didUpdateWidget(_CompletionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncItemKeys();
    if (widget.selectedIndex != oldWidget.selectedIndex ||
        !identical(widget.completions, oldWidget.completions)) {
      // Deferred a frame: the selected row is taller than the others (it
      // grows a detail line — see the class doc comment), so scrolling
      // against this frame's *old* layout would target the wrong offset.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollSelectedIntoView(),
      );
    }
  }

  void _syncItemKeys() {
    if (_itemKeys.length == widget.completions.length) return;
    _itemKeys
      ..clear()
      ..addAll(List.generate(widget.completions.length, (_) => GlobalKey()));
  }

  // [attempt] bounds a possible retry (see below) at 1 — never grows
  // without a terminating jump between calls, so this can't loop forever.
  void _scrollSelectedIntoView([int attempt = 0]) {
    if (!mounted ||
        !_scrollController.hasClients ||
        widget.completions.isEmpty) {
      return;
    }
    final index = widget.selectedIndex;
    final itemContext = _itemKeys[index].currentContext;
    if (itemContext != null) {
      // The precise case: the target row is already built, so its real
      // height — taller than the others once it's the selected one, see
      // the class doc comment — is already known and reflected in layout.
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 100),
      );
      return;
    }
    if (attempt > 0) {
      return; // already retried once; the row still won't build — give up rather than loop
    }
    // No context: this row was never built (lazily-built ListView), which
    // is exactly what _moveCompletionSelection's wraparound reaches — the
    // opposite end from wherever the selection just was. The two ends have
    // an exact target offset that doesn't need a context, so jump there —
    // but jumpTo uses an *estimate* for a not-yet-built row's extent, which
    // assumes single-line height and so lands short of a row that's about
    // to grow a detail line once selected. That coarse jump only serves to
    // force the row to actually get built at the new scroll position;
    // requesting one more frame lets the ensureVisible branch above correct
    // for its real (now-known) height.
    if (index == 0) {
      _scrollController.jumpTo(0);
    } else if (index == widget.completions.length - 1) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    } else {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollSelectedIntoView(attempt + 1),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          controller: _scrollController,
          // Default (fade-in-on-scroll-only) visibility means there's
          // nothing to grab until a scroll gesture happens to reveal it
          // first — effectively undraggable. ScrollbarPainter itself already
          // skips painting (and hit-testing) when the list doesn't overflow,
          // so this doesn't paint a dead thumb over a short completion list.
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: widget.completions.length,
            itemBuilder: (context, index) {
              final item = widget.completions[index];
              final selected = index == widget.selectedIndex;
              return Material(
                key: _itemKeys[index],
                color: selected
                    ? colorScheme.primaryContainer
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => widget.onSelected(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              typstCompletionKindIcon(item.kind.tag),
                              size: 16,
                              color: typstCompletionKindColor(item.kind.tag),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.label,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (selected && item.detail != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 24),
                            child: Text(
                              item.detail!,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 3,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
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
}
