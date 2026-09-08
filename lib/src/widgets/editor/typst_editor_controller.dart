import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../document/typst_diagnostic.dart';
import '../../document/typst_highlight.dart';
import '../../document/typst_session.dart';
import 'typst_syntax_theme.dart';

/// A [TextEditingController] that colors Typst source using
/// [TypstSession.highlight] and underlines compiler diagnostics from
/// [TypstSession.results].
///
/// Both are wired up automatically: pass a [session] that the same source is
/// also fed to (typically via [TypstSession.updateSource]), and highlighting
/// and diagnostics stay in sync with it without further plumbing. This
/// controller keeps its own subscription to [TypstSession.results] for that —
/// [TypstSession.results] is a broadcast stream, so other code (e.g. a page
/// reacting to compile status) can freely listen to it too without taking
/// diagnostics away from here.
///
/// Known gap: unlike the stock [TextEditingController], this does not
/// visualize the IME composing region (the underline shown while composing
/// CJK input). Composition itself is unaffected — only that visual cue is
/// missing.
class TypstEditorController extends TextEditingController {
  TypstEditorController({
    required TypstSession session,
    TypstSyntaxTheme? theme,
    this.errorColor = const Color(0xFFD73A49),
    this.warningColor = const Color(0xFFE36209),
    String text = '',
  }) : _session = session,
       theme = theme ?? TypstSyntaxTheme.defaultTheme,
       super(text: text) {
    _resultsSubscription = session.results.listen((result) {
      _diagnostics = result.diagnostics;
      notifyListeners();
    });
    _requestHighlight();
  }

  final TypstSession _session;
  late StreamSubscription<TypstCompileResult> _resultsSubscription;

  /// The tag → style mapping used to color source. Assigning a new value
  /// repaints without recomputing the highlight tree.
  TypstSyntaxTheme theme;

  /// Wavy-underline color for error diagnostics.
  Color errorColor;

  /// Wavy-underline color for warning diagnostics.
  Color warningColor;

  List<TypstDiagnostic> _diagnostics = const [];

  TypstHighlightNode? _tree;
  // The exact text `_tree` was computed for, so a build that races ahead of
  // a still-in-flight highlight call can fall back to plain text instead of
  // rendering stale spans whose concatenated text no longer matches `text`.
  String? _treeText;
  bool _highlightInFlight = false;
  bool _highlightStale = false;
  // Bumped per dispatched request. `notifyListeners()` below can run a
  // listener that synchronously assigns `text` again (e.g. an app-level
  // auto-formatter), which re-enters `_requestHighlight` while this
  // `.then` is still on the stack and dispatches a second request before
  // this one reaches its own tail check. `source == text` alone can't tell
  // those two apart when the reentrant edit round-trips back to this
  // request's source; the id can.
  int _highlightRequestId = 0;

  void _requestHighlight() {
    if (_highlightInFlight) {
      _highlightStale = true;
      return;
    }
    _highlightInFlight = true;
    _highlightStale = false;
    final source = text;
    final requestId = ++_highlightRequestId;
    _session.highlight(source).then((tree) {
      _highlightInFlight = false;
      if (requestId == _highlightRequestId && source == text) {
        _tree = tree;
        _treeText = source;
        notifyListeners();
      }
      if (_highlightStale) _requestHighlight();
    });
  }

  @override
  set value(TextEditingValue newValue) {
    final textChanged = newValue.text != text;
    super.value = newValue;
    if (textChanged) _requestHighlight();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    return debugBuildSpan(style: style);
  }

  /// The same span-building logic [buildTextSpan] uses, without requiring a
  /// [BuildContext] — for tests.
  @visibleForTesting
  TextSpan debugBuildSpan({TextStyle? style}) {
    final tree = _tree;
    if (tree == null || _treeText != text) {
      return TextSpan(text: text, style: style);
    }
    final cursor = _Utf16Cursor();
    return TextSpan(style: style, children: [_buildNode(tree, cursor)]);
  }

  /// Whether a highlight computed for the current [text] is ready — i.e.
  /// whether [debugBuildSpan] will use it rather than falling back to plain
  /// text. For tests.
  @visibleForTesting
  bool get debugHasFreshTree => _tree != null && _treeText == text;

  TextSpan _buildNode(TypstHighlightNode node, _Utf16Cursor cursor) {
    final tagStyle = node.tag != null ? theme.styleFor(node.tag!) : null;
    if (node.children.isEmpty) {
      return _leafSpan(node.text, tagStyle, cursor);
    }
    return TextSpan(style: tagStyle, children: [for (final child in node.children) _buildNode(child, cursor)]);
  }

  /// Splits one leaf's text at diagnostic boundaries so the overlapping
  /// portion(s) get an additional wavy underline on top of [tagStyle].
  TextSpan _leafSpan(String text, TextStyle? tagStyle, _Utf16Cursor cursor) {
    final start = cursor.offset;
    final end = start + text.length;
    cursor.offset = end;
    if (text.isEmpty) return TextSpan(text: text, style: tagStyle);

    final covering = [
      for (final d in _diagnostics)
        if (d.sourceStart != null && d.sourceEnd != null && d.sourceStart! < end && d.sourceEnd! > start) d,
    ];
    if (covering.isEmpty) return TextSpan(text: text, style: tagStyle);

    final cuts = <int>{start, end};
    for (final d in covering) {
      cuts
        ..add(d.sourceStart!.clamp(start, end))
        ..add(d.sourceEnd!.clamp(start, end));
    }
    final points = cuts.toList()..sort();

    final children = <TextSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final segStart = points[i];
      final segEnd = points[i + 1];
      if (segStart == segEnd) continue;
      final segment = text.substring(segStart - start, segEnd - start);
      final severity = _worstSeverity(covering, segStart, segEnd);
      final segStyle = severity == null ? tagStyle : _withDiagnostic(tagStyle, severity);
      children.add(TextSpan(text: segment, style: segStyle));
    }
    return TextSpan(children: children);
  }

  TypstDiagnosticSeverity? _worstSeverity(List<TypstDiagnostic> diagnostics, int segStart, int segEnd) {
    TypstDiagnosticSeverity? worst;
    for (final d in diagnostics) {
      if (d.sourceStart! >= segEnd || d.sourceEnd! <= segStart) continue;
      if (d.severity == TypstDiagnosticSeverity.error) return TypstDiagnosticSeverity.error;
      worst = TypstDiagnosticSeverity.warning;
    }
    return worst;
  }

  TextStyle _withDiagnostic(TextStyle? base, TypstDiagnosticSeverity severity) {
    final decoration = TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.wavy,
      decorationColor: severity == TypstDiagnosticSeverity.error ? errorColor : warningColor,
    );
    return (base ?? const TextStyle()).merge(decoration);
  }

  @override
  void dispose() {
    _resultsSubscription.cancel();
    super.dispose();
  }
}

class _Utf16Cursor {
  int offset = 0;
}
