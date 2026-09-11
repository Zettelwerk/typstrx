import 'package:flutter/material.dart';

/// A [TextMagnifierConfiguration] matching pdfrx's magnifier styling — see
/// [TypstEditorSelectionControls] for why the editor can't share the
/// reader's exact re-render/backdrop-filter technique, only its look.
final typstEditorMagnifierConfiguration = TextMagnifierConfiguration(
  magnifierBuilder:
      (
        BuildContext context,
        MagnifierController controller,
        ValueNotifier<MagnifierInfo> magnifierInfo,
      ) {
        return _TypstEditorMagnifier(magnifierInfo: magnifierInfo);
      },
);

// Same values the reader's magnifier uses (see typst_viewer_selection.dart)
// — kept in sync by eye rather than shared, since the two live in separate
// library parts with no natural shared-constants file yet.
const _magnifierSize = Size(160, 48);
const _magnifierAboveFocalPoint = 26.0;
const _magnifierScale = 1.5;
const _magnifierBorderRadius = 30.0;

/// Tracks the touch point reported by [magnifierInfo] and floats a
/// [RawMagnifier] above it, styled like pdfrx's own magnifier decoration
/// (rounded rect, radius 30, black26 shadow, blur 8 / spread 2).
class _TypstEditorMagnifier extends StatelessWidget {
  const _TypstEditorMagnifier({required this.magnifierInfo});

  final ValueNotifier<MagnifierInfo> magnifierInfo;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MagnifierInfo>(
      valueListenable: magnifierInfo,
      builder: (context, info, child) {
        final focal = Offset(
          info.globalGesturePosition.dx.clamp(
            info.currentLineBoundaries.left,
            info.currentLineBoundaries.right,
          ),
          info.globalGesturePosition.dy,
        );
        return Positioned(
          left: focal.dx - _magnifierSize.width / 2,
          top: focal.dy - _magnifierAboveFocalPoint - _magnifierSize.height / 2,
          child: IgnorePointer(
            child: RawMagnifier(
              size: _magnifierSize,
              magnificationScale: _magnifierScale,
              focalPointOffset: Offset(
                0,
                _magnifierAboveFocalPoint + _magnifierSize.height / 2,
              ),
              decoration: MagnifierDecoration(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_magnifierBorderRadius),
                ),
                shadows: const [
                  BoxShadow(color: Color(0x42000000), blurRadius: 8, spreadRadius: 2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [TypstCodeEditor]'s default touch selection handles — a port of pdfrx's
/// selection-handle shape (a solid 30x30 right triangle "flag", pinned by
/// its right-angle corner to the text edge it marks) so touch selection
/// looks and feels the same across the reader and the editor.
///
/// Unlike the reader's own handles (see `_TriangleHandlePainter` in
/// `typst_viewer_selection.dart`), `TextSelectionControls.buildHandle` gets
/// no per-frame drag/hover state from `EditableText`, so these always paint
/// in pdfrx's "normal" state (alpha 0.7, shadow on) — there's no hook to
/// switch to "dragging" (alpha 1, no shadow) the way the reader's own
/// gesture-tracked overlay can.
///
/// pdfrx has no collapsed (caret-only) handle — Typst source is plain text,
/// not a PDF page, so there's no upstream shape to port for it. A small
/// solid circle hanging below the caret is used instead, distinct from the
/// selection-endpoint triangles so it doesn't look like a stray selection
/// handle when nothing is selected.
class TypstEditorSelectionControls extends TextSelectionControls
    with TextSelectionHandleControls {
  TypstEditorSelectionControls({this.color});

  /// Handle color. Defaults to the ambient [ColorScheme.primary].
  final Color? color;

  static const _handleSize = 30.0;
  static const _collapsedDiameter = 12.0;

  // `EditableText` always feeds the *bottom*-of-line point as the anchor
  // for every handle type (see RenderEditable._paintHandleLayers /
  // getEndpointsForSelection) — there's no per-type top/bottom choice the
  // way the reader's own overlay gets to make, and — a real API limit, not
  // a design choice — `getHandleSize` isn't even told which [type] it's
  // sizing, so it can't return a different size per type either. Every
  // handle's box is therefore made the full line height plus the flag
  // (`textLineHeight + _handleSize` tall) uniformly, whether or not a given
  // type actually needs the extra room:
  //
  //  - left (start): the flag is drawn in the box's *top* 30px, with the
  //    anchor pinned to the box's bottom-right — since that bottom-right
  //    corner is what lines up with the fixed bottom-of-line feed point,
  //    the flag itself (a whole line height above that corner) ends up
  //    sitting right at the *top* of the line, tip touching it, matching
  //    pdfrx's look (and the reader's own — see typst_viewer_selection.dart).
  //  - right (end) and collapsed: the flag/circle is also drawn in the
  //    box's top 30px, anchor pinned to the box's top-left (0,0) — so it
  //    sits exactly at the bottom-of-line feed point, same as before this
  //    box was made taller. The extra height below is unused, inert space
  //    (a larger hit target, not a visual change).
  @override
  Size getHandleSize(double textLineHeight) => Size(_handleSize, textLineHeight + _handleSize);

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    return switch (type) {
      TextSelectionHandleType.left => Offset(_handleSize, textLineHeight + _handleSize),
      TextSelectionHandleType.right => Offset.zero,
      TextSelectionHandleType.collapsed => Offset(_handleSize / 2, 0),
    };
  }

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final handleColor = color ?? Theme.of(context).colorScheme.primary;
    final flag = switch (type) {
      TextSelectionHandleType.left => CustomPaint(
        size: const Size(_handleSize, _handleSize),
        painter: _TriangleHandlePainter(path: _startHandlePath(), color: handleColor),
      ),
      TextSelectionHandleType.right => CustomPaint(
        size: const Size(_handleSize, _handleSize),
        painter: _TriangleHandlePainter(path: _endHandlePath(), color: handleColor),
      ),
      TextSelectionHandleType.collapsed => CustomPaint(
        size: const Size(_handleSize, _handleSize),
        painter: _CollapsedHandlePainter(color: handleColor),
      ),
    };
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.translucent,
      child: SizedBox(
        width: _handleSize,
        height: textLineHeight + _handleSize,
        child: Column(children: [flag, SizedBox(height: textLineHeight)]),
      ),
    );
  }
}

Path _startHandlePath() => Path()
  ..moveTo(30, 0)
  ..lineTo(30, 30)
  ..lineTo(0, 30)
  ..close();

Path _endHandlePath() => Path()
  ..moveTo(0, 0)
  ..lineTo(30, 0)
  ..lineTo(0, 30)
  ..close();

/// Paints one triangle handle in pdfrx's "normal" state — see the class
/// doc on [TypstEditorSelectionControls] for why "dragging" isn't
/// reachable here.
class _TriangleHandlePainter extends CustomPainter {
  _TriangleHandlePainter({required this.path, required this.color});

  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawShadow(path, Colors.black, 4, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _TriangleHandlePainter oldDelegate) =>
      oldDelegate.path != path || oldDelegate.color != color;
}

/// The caret-only (collapsed selection) handle — a small solid circle
/// hanging below the caret, its own top-center pinned to the caret's
/// bottom point. No pdfrx equivalent to port; see the class doc above.
class _CollapsedHandlePainter extends CustomPainter {
  _CollapsedHandlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      size.width / 2,
      TypstEditorSelectionControls._collapsedDiameter / 2,
    );
    const radius = TypstEditorSelectionControls._collapsedDiameter / 2;
    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      Colors.black,
      4,
      true,
    );
    canvas.drawCircle(center, radius, Paint()..color = color.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _CollapsedHandlePainter oldDelegate) => oldDelegate.color != color;
}
