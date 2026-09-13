import 'package:flutter/widgets.dart';

/// A line-number column for [TypstCodeEditor], scroll-synced with the
/// editor's own [ScrollController]. Only a logical source line's first
/// wrapped row gets a number — matching how most code editors handle soft
/// wrap — never one per visual row.
///
/// Line tops are estimated by laying out each source line on its own with
/// [textWidth] as the wrap width, using the same [style] the editor itself
/// renders with. This is an approximation, not a read of `EditableText`'s
/// actual internal layout (which exposes no line-metrics API): it ignores
/// any `strutStyle`/`textHeightBehavior` the editor might be using, and can
/// drift a pixel or two from the real caret geometry on unusual fonts. Good
/// enough for a gutter; not load-bearing for anything caret-accurate.
class TypstLineNumberGutter extends StatefulWidget {
  const TypstLineNumberGutter({
    super.key,
    required this.text,
    required this.style,
    required this.scrollController,
    required this.textWidth,
    required this.width,
    required this.color,
  });

  /// The editor's current plain text.
  final String text;

  /// Must match the editor's own text style for the wrap-width estimate
  /// (and thus each line's vertical position) to line up with the real
  /// text.
  final TextStyle style;

  /// The same [ScrollController] passed to the editor's own `EditableText`
  /// — this gutter never creates its own scrollable, it just mirrors this
  /// controller's offset.
  final ScrollController scrollController;

  /// The wrap width to lay each source line out at — the editor's own
  /// content width, i.e. the space to the right of this gutter.
  final double textWidth;

  /// This gutter's own width, as computed by [typstLineNumberGutterWidth].
  final double width;

  final Color color;

  @override
  State<TypstLineNumberGutter> createState() => _TypstLineNumberGutterState();
}

class _TypstLineNumberGutterState extends State<TypstLineNumberGutter> {
  List<double> _lineTops = const [0];

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _recomputeLineTops();
  }

  @override
  void didUpdateWidget(TypstLineNumberGutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
    if (oldWidget.text != widget.text ||
        oldWidget.textWidth != widget.textWidth ||
        oldWidget.style != widget.style) {
      _recomputeLineTops();
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() => setState(() {});

  void _recomputeLineTops() {
    final lines = widget.text.split('\n');
    final tops = <double>[];
    var y = 0.0;
    final maxWidth = widget.textWidth > 0 ? widget.textWidth : double.infinity;
    for (final line in lines) {
      tops.add(y);
      final painter = TextPainter(
        // An empty line still needs a real line box to measure — a blank
        // TextSpan collapses to zero height.
        text: TextSpan(text: line.isEmpty ? ' ' : line, style: widget.style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      y += painter.height;
      painter.dispose();
    }
    _lineTops = tops;
  }

  @override
  Widget build(BuildContext context) {
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    return SizedBox(
      width: widget.width,
      child: ClipRect(
        child: Stack(
          children: [
            for (var i = 0; i < _lineTops.length; i++)
              Positioned(
                top: _lineTops[i] - scrollOffset,
                right: 4,
                left: 0,
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.right,
                  style: widget.style.copyWith(color: widget.color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The gutter width that fits every line number in [lineCount] at [style],
/// plus a little breathing room — sized off the widest digit run rather
/// than the actual text, so it doesn't jitter as the digit count changes
/// line by line, only as the overall line count crosses a power of ten.
double typstLineNumberGutterWidth(TextStyle style, int lineCount) {
  final digits = '$lineCount'.length.clamp(2, 6);
  final painter = TextPainter(
    text: TextSpan(text: '9' * digits, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width + 12;
}
