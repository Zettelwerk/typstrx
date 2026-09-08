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
    this.autoClosePairs = const {'(': ')', '[': ']', '{': '}', '"': '"'},
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

  /// The session backing this controller — for editor chrome built on top
  /// (e.g. a completion popup) that needs [TypstSession.completions]/
  /// [TypstSession.hover]/[TypstSession.lastCompiledSource] directly.
  TypstSession get session => _session;

  /// The tag → style mapping used to color source. Assigning a new value
  /// repaints without recomputing the highlight tree.
  TypstSyntaxTheme theme;

  /// Wavy-underline color for error diagnostics.
  Color errorColor;

  /// Wavy-underline color for warning diagnostics.
  Color warningColor;

  /// Typed-opener → auto-inserted-closer pairs applied as the user types
  /// (see [_applyAutoClose]). Assigning a new map takes effect on the next
  /// edit; pass `{}` to disable auto-closing entirely.
  ///
  /// Deliberately excludes `$`, Typst's math-mode delimiter: unlike a
  /// bracket it toggles a mode rather than opening a well-nested region, and
  /// is at least as often typed to wrap an existing selection (which this
  /// never does — see [_applyAutoClose]) as to open a fresh one. Add it
  /// yourself here if that heuristic still works for how you use it.
  Map<String, String> autoClosePairs;

  /// Offsets in the current [text] of closer characters *this controller*
  /// inserted (not ones the user typed themselves), so that a matching
  /// typed closer types over it instead of duplicating it, and backspace
  /// right after an opener deletes both. Cleared on any edit whose shape we
  /// don't specifically recognize in [_applyAutoClose] — safer to stop
  /// tracking than to guess against text that moved in an unknown way.
  final Set<int> _pendingAutoClose = {};

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
    final adjusted = autoClosePairs.isEmpty ? newValue : _applyAutoClose(value, newValue);
    final textChanged = adjusted.text != text;
    super.value = adjusted;
    if (textChanged) _requestHighlight();
  }

  /// Implements auto-closing brackets/quotes on top of whatever edit the
  /// text input system already produced, by comparing it against [oldValue]
  /// (the controller's value just before this edit).
  ///
  /// Only two edit shapes are recognized — a single character inserted at a
  /// collapsed caret, and a single character deleted by backspace at a
  /// collapsed caret — matched structurally (identical text on both sides
  /// of the change point) rather than assumed from the selection alone.
  /// Anything else (paste, IME composition committing multiple characters,
  /// a programmatic bulk `text =` assignment, replacing a selection) falls
  /// through unchanged and resets [_pendingAutoClose], on the same
  /// safety-over-guessing principle as the rest of this method:
  ///
  ///  * Typing an opener inserts its closer right after the caret and
  ///    leaves the caret between them — unless the character right after
  ///    the caret is a word character, so typing `(` before `foo` gives
  ///    `(foo`, not `(foo)`.
  ///  * Typing a closer that matches one this controller just auto-inserted
  ///    at the caret types over it instead of duplicating it.
  ///  * Backspacing an opener whose very next character is a closer this
  ///    controller auto-inserted deletes both, not just the opener.
  ///  * A non-collapsed [TextEditingValue.composing] range (an IME
  ///    composition in progress) is left alone — inserting a closer next to
  ///    a live composing range would land inside it.
  ///  * Replacing a selection is never treated as "wrap the selection in
  ///    the pair" — it's just whatever plain replacement the input system
  ///    already produced. Deliberately out of scope for now: it needs its
  ///    own caret-placement decision (select the wrapped text back? leave
  ///    the caret after it?) that the rest of this method's structural
  ///    matching doesn't answer for free.
  TextEditingValue _applyAutoClose(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text == oldValue.text) return newValue;
    if (!newValue.composing.isCollapsed) {
      _pendingAutoClose.clear();
      return newValue;
    }

    final lenDelta = newValue.text.length - oldValue.text.length;

    if (lenDelta == 1 &&
        oldValue.selection.isValid &&
        oldValue.selection.isCollapsed &&
        newValue.selection.isValid &&
        newValue.selection.isCollapsed) {
      final p = oldValue.selection.baseOffset;
      if (newValue.selection.baseOffset == p + 1 &&
          p >= 0 &&
          p <= oldValue.text.length &&
          newValue.text.substring(0, p) == oldValue.text.substring(0, p) &&
          newValue.text.substring(p + 1) == oldValue.text.substring(p)) {
        return _afterInsert(oldValue, newValue, p, newValue.text[p]);
      }
    }

    if (lenDelta == -1 &&
        oldValue.selection.isValid &&
        oldValue.selection.isCollapsed &&
        newValue.selection.isValid &&
        newValue.selection.isCollapsed) {
      final q = newValue.selection.baseOffset;
      if (oldValue.selection.baseOffset == q + 1 &&
          q >= 0 &&
          q < oldValue.text.length &&
          newValue.text == oldValue.text.substring(0, q) + oldValue.text.substring(q + 1)) {
        return _afterBackspace(oldValue, newValue, q);
      }
    }

    _pendingAutoClose.clear();
    return newValue;
  }

  /// Handles a single character [typed] inserted at offset [p] (its
  /// position in [oldValue].text, before insertion).
  TextEditingValue _afterInsert(TextEditingValue oldValue, TextEditingValue newValue, int p, String typed) {
    if (_pendingAutoClose.contains(p) && oldValue.text[p] == typed) {
      _pendingAutoClose.remove(p);
      return oldValue.copyWith(selection: TextSelection.collapsed(offset: p + 1));
    }

    final closer = autoClosePairs[typed];
    final nextChar = p < oldValue.text.length ? oldValue.text[p] : '';
    final shouldPair = closer != null && !_isWordChar(nextChar);

    _shiftPending(from: p, delta: shouldPair ? 2 : 1);
    if (!shouldPair) return newValue;

    final text = '${oldValue.text.substring(0, p)}$typed$closer${oldValue.text.substring(p)}';
    _pendingAutoClose.add(p + 1);
    return newValue.copyWith(text: text, selection: TextSelection.collapsed(offset: p + 1));
  }

  /// Handles a backspace deleting the character at offset [q] (its position
  /// in [oldValue].text).
  TextEditingValue _afterBackspace(TextEditingValue oldValue, TextEditingValue newValue, int q) {
    final deletesPair =
        _pendingAutoClose.contains(q + 1) &&
        q + 1 < oldValue.text.length &&
        autoClosePairs[oldValue.text[q]] == oldValue.text[q + 1];
    if (!deletesPair) {
      _pendingAutoClose.remove(q);
      _shiftPending(from: q + 1, delta: -1);
      return newValue;
    }

    _pendingAutoClose.remove(q + 1);
    _shiftPending(from: q + 2, delta: -2);
    final text = oldValue.text.substring(0, q) + oldValue.text.substring(q + 2);
    return newValue.copyWith(text: text, selection: TextSelection.collapsed(offset: q));
  }

  /// Adds [delta] to every tracked offset `>= from` — for keeping
  /// [_pendingAutoClose] valid across an edit that shifts text around a
  /// point without otherwise disturbing it.
  void _shiftPending({required int from, required int delta}) {
    final shifted = <int>{for (final o in _pendingAutoClose) o >= from ? o + delta : o};
    _pendingAutoClose
      ..clear()
      ..addAll(shifted);
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

/// Whether [s] (empty, or a single UTF-16 code unit) is a letter, digit, or
/// underscore — ASCII only. Used to decide whether an auto-inserted closer
/// would land against the start of a word rather than open space; a false
/// negative on non-ASCII identifier characters just means an unnecessary
/// pair sometimes gets added, not a wrong edit.
bool _isWordChar(String s) {
  if (s.isEmpty) return false;
  final c = s.codeUnitAt(0);
  return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
}
