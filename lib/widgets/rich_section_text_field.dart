import 'package:flutter/material.dart';

import '../models/rule_section.dart';

/// Champ multiligne avec gras visuel (sans balises markdown visibles).
class RichSectionTextField extends StatefulWidget {
  final List<RuleTextSpan> initialSpans;
  final ValueChanged<List<RuleTextSpan>> onChanged;
  final int minLines;

  const RichSectionTextField({
    super.key,
    required this.initialSpans,
    required this.onChanged,
    this.minLines = 4,
  });

  @override
  State<RichSectionTextField> createState() => _RichSectionTextFieldState();
}

class _RichSectionTextFieldState extends State<RichSectionTextField> {
  late final _RichTextController _controller;
  late final FocusNode _focusNode;
  TextSelection _lastSelection = const TextSelection.collapsed(offset: 0);
  bool _emitting = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _controller = _RichTextController.fromSpans(widget.initialSpans);
    _controller.addListener(_emit);
    _controller.addListener(_trackSelection);
  }

  @override
  void didUpdateWidget(RichSectionTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Jamais réécrire le controller tant qu'on a le focus (frappe / gras).
    if (_focusNode.hasFocus || _emitting) return;
    final current = _controller.toSpans();
    if (!_spansEqual(current, widget.initialSpans)) {
      _controller.setSpans(widget.initialSpans, keepSelection: true);
    }
  }

  static bool _spansEqual(List<RuleTextSpan> a, List<RuleTextSpan> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].text != b[i].text || a[i].bold != b[i].bold) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.removeListener(_emit);
    _controller.removeListener(_trackSelection);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _trackSelection() {
    final sel = _controller.selection;
    if (sel.isValid) _lastSelection = sel;
  }

  void _emit() {
    if (_emitting) return;
    _emitting = true;
    try {
      widget.onChanged(_controller.toSpans());
    } finally {
      _emitting = false;
    }
  }

  TextSelection _effectiveSelection() {
    final sel = _controller.selection;
    if (sel.isValid && sel.start >= 0) return sel;
    return _lastSelection;
  }

  void _toggleBold() {
    final sel = _effectiveSelection();
    var start = sel.start.clamp(0, _controller.text.length);
    var end = sel.end.clamp(0, _controller.text.length);
    if (start > end) {
      final t = start;
      start = end;
      end = t;
    }
    if (start == end) return;
    _controller.toggleBold(start, end);
    _lastSelection = TextSelection(baseOffset: start, extentOffset: end);
    _emit();
    // Pas de setState : le controller notifie déjà le TextField.
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: 'Gras',
            visualDensity: VisualDensity.compact,
            onPressed: _toggleBold,
            icon: const Icon(Icons.format_bold, size: 20),
          ),
        ),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          minLines: widget.minLines,
          maxLines: 12,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
            hintText: 'Saisissez le contenu de la section…',
          ),
        ),
      ],
    );
  }
}

class _RichTextController extends TextEditingController {
  List<RuleTextSpan> _spans = [const RuleTextSpan(text: '')];

  _RichTextController.fromSpans(List<RuleTextSpan> spans) : super() {
    setSpans(spans);
  }

  void setSpans(List<RuleTextSpan> spans, {bool keepSelection = false}) {
    final sel = selection;
    _spans = spans.isEmpty ? [const RuleTextSpan(text: '')] : List.of(spans);
    final nextText = _spans.map((s) => s.text).join();
    final offset = keepSelection && sel.isValid
        ? sel.extentOffset.clamp(0, nextText.length)
        : nextText.length;
    value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  List<RuleTextSpan> toSpans() {
    if (_spans.isEmpty) return [const RuleTextSpan(text: '')];
    return List.of(_spans);
  }

  void toggleBold(int start, int end) {
    final next = <RuleTextSpan>[];
    var offset = 0;
    for (final span in _spans) {
      final spanStart = offset;
      final spanEnd = offset + span.text.length;
      offset = spanEnd;
      if (spanEnd <= start || spanStart >= end) {
        next.add(span);
        continue;
      }
      final localStart = (start - spanStart).clamp(0, span.text.length);
      final localEnd = (end - spanStart).clamp(0, span.text.length);
      if (localStart > 0) {
        next.add(
          RuleTextSpan(text: span.text.substring(0, localStart), bold: span.bold),
        );
      }
      next.add(
        RuleTextSpan(
          text: span.text.substring(localStart, localEnd),
          bold: !span.bold,
        ),
      );
      if (localEnd < span.text.length) {
        next.add(
          RuleTextSpan(text: span.text.substring(localEnd), bold: span.bold),
        );
      }
    }
    _spans = _mergeAdjacent(next);
    final joined = _spans.map((s) => s.text).join();
    value = TextEditingValue(
      text: joined,
      selection: TextSelection(baseOffset: start, extentOffset: end),
    );
  }

  static List<RuleTextSpan> _mergeAdjacent(List<RuleTextSpan> spans) {
    if (spans.isEmpty) return [const RuleTextSpan(text: '')];
    final out = <RuleTextSpan>[spans.first];
    for (var i = 1; i < spans.length; i++) {
      final prev = out.last;
      final cur = spans[i];
      if (prev.bold == cur.bold) {
        out[out.length - 1] = RuleTextSpan(
          text: prev.text + cur.text,
          bold: prev.bold,
        );
      } else {
        out.add(cur);
      }
    }
    final cleaned = out.where((s) => s.text.isNotEmpty).toList();
    return cleaned.isEmpty ? [const RuleTextSpan(text: '')] : cleaned;
  }

  @override
  set value(TextEditingValue newValue) {
    final oldText = text;
    final newText = newValue.text;
    if (newText == oldText) {
      super.value = newValue;
      return;
    }
    _spans = _applyTextEdit(_spans, oldText, newText, newValue.selection);
    super.value = newValue;
  }

  /// Préserve le gras autour de l'édition (ne flatten plus tout en un span).
  static List<RuleTextSpan> _applyTextEdit(
    List<RuleTextSpan> spans,
    String oldText,
    String newText,
    TextSelection selection,
  ) {
    if (oldText == newText) return spans;
    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < newText.length &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var oldSuffix = oldText.length;
    var newSuffix = newText.length;
    while (oldSuffix > prefix &&
        newSuffix > prefix &&
        oldText.codeUnitAt(oldSuffix - 1) ==
            newText.codeUnitAt(newSuffix - 1)) {
      oldSuffix--;
      newSuffix--;
    }
    final inserted = newText.substring(prefix, newSuffix);

    final before = <RuleTextSpan>[];
    final after = <RuleTextSpan>[];
    var offset = 0;
    bool? insertBold;
    for (final span in spans) {
      final spanStart = offset;
      final spanEnd = offset + span.text.length;
      offset = spanEnd;

      if (spanEnd <= prefix) {
        before.add(span);
        if (spanEnd == prefix) insertBold = span.bold;
        continue;
      }
      if (spanStart >= oldSuffix) {
        after.add(span);
        continue;
      }

      // Span chevauche la zone supprimée.
      final keepStart = (prefix - spanStart).clamp(0, span.text.length);
      final keepEnd = (oldSuffix - spanStart).clamp(0, span.text.length);
      if (keepStart > 0) {
        before.add(
          RuleTextSpan(text: span.text.substring(0, keepStart), bold: span.bold),
        );
        insertBold = span.bold;
      } else {
        insertBold ??= span.bold;
      }
      if (keepEnd < span.text.length) {
        after.add(
          RuleTextSpan(text: span.text.substring(keepEnd), bold: span.bold),
        );
      }
    }

    final next = <RuleTextSpan>[...before];
    if (inserted.isNotEmpty) {
      next.add(RuleTextSpan(text: inserted, bold: insertBold ?? false));
    }
    next.addAll(after);
    return _mergeAdjacent(next);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final children = <TextSpan>[];
    for (final span in _spans) {
      if (span.text.isEmpty) continue;
      children.add(
        TextSpan(
          text: span.text,
          style: style?.copyWith(
            fontWeight: span.bold ? FontWeight.bold : style.fontWeight,
          ),
        ),
      );
    }
    if (children.isEmpty) {
      return TextSpan(style: style, text: '');
    }
    return TextSpan(style: style, children: children);
  }
}

/// Affichage lecture seule des spans.
class RichSectionText extends StatelessWidget {
  final List<RuleTextSpan> spans;
  final TextStyle? style;

  const RichSectionText({super.key, required this.spans, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    return Text.rich(
      TextSpan(
        children: spans.map((s) {
          return TextSpan(
            text: s.text,
            style: base?.copyWith(
              fontWeight: s.bold ? FontWeight.bold : base.fontWeight,
            ),
          );
        }).toList(),
      ),
    );
  }
}
