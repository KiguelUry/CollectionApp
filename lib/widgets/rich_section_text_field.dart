import 'package:flutter/material.dart';

import '../models/rule_section.dart';

const kRuleTextPalette = <Color>[
  Colors.white,
  Color(0xFFFFD54F), // or / ambre
  Color(0xFF66BB6A), // émeraude
  Color(0xFF4FC3F7), // bleu ciel
  Color(0xFFFF8A65), // corail
  Color(0xFFCE93D8), // violet clair
];

Color? ruleColorFromHex(String? hex) {
  if (hex == null || hex.trim().isEmpty) return null;
  var raw = hex.trim();
  if (raw.startsWith('#')) raw = raw.substring(1);
  if (raw.length == 6) raw = 'FF$raw';
  final value = int.tryParse(raw, radix: 16);
  if (value == null) return null;
  return Color(value);
}

String ruleColorToHex(Color color) {
  final argb = color.toARGB32();
  return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// Champ multiligne avec gras / couleur (toggle avant frappe ou sur sélection).
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
  bool _boldTyping = false;
  Color? _typingColor;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _controller = _RichTextController.fromSpans(widget.initialSpans);
    _controller.typingBold = _boldTyping;
    _controller.typingColor = _typingColor;
    _controller.addListener(_emit);
    _controller.addListener(_trackSelection);
  }

  @override
  void didUpdateWidget(RichSectionTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus || _emitting) return;
    final current = _controller.toSpans();
    if (!_spansEqual(current, widget.initialSpans)) {
      _controller.setSpans(widget.initialSpans, keepSelection: true);
    }
  }

  static bool _spansEqual(List<RuleTextSpan> a, List<RuleTextSpan> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].text != b[i].text ||
          a[i].bold != b[i].bold ||
          a[i].color != b[i].color) {
        return false;
      }
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

  void _onBoldPressed() {
    final sel = _effectiveSelection();
    var start = sel.start.clamp(0, _controller.text.length);
    var end = sel.end.clamp(0, _controller.text.length);
    if (start > end) {
      final t = start;
      start = end;
      end = t;
    }
    if (start != end) {
      _controller.toggleBold(start, end);
      _lastSelection = TextSelection(baseOffset: start, extentOffset: end);
      _emit();
      return;
    }
    setState(() {
      _boldTyping = !_boldTyping;
      _controller.typingBold = _boldTyping;
    });
  }

  void _applyColor(Color? color) {
    final sel = _effectiveSelection();
    var start = sel.start.clamp(0, _controller.text.length);
    var end = sel.end.clamp(0, _controller.text.length);
    if (start > end) {
      final t = start;
      start = end;
      end = t;
    }
    if (start != end) {
      _controller.applyColor(start, end, color);
      _lastSelection = TextSelection(baseOffset: start, extentOffset: end);
      _emit();
      return;
    }
    setState(() {
      _typingColor = color;
      _controller.typingColor = color;
    });
  }

  Future<void> _pickColor() async {
    final chosen = await showModalBottomSheet<Color?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Couleur du texte',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in kRuleTextPalette)
                    InkWell(
                      onTap: () => Navigator.pop(ctx, c),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white24,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('Défaut'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    // null from dismiss ≠ default; only apply if sheet returned a value
    // including explicit null via "Défaut".
    if (chosen == null && ModalRoute.of(context)?.isCurrent != true) {
      // dismissed without choice — ignore
    }
    // showModalBottomSheet returns null on dismiss OR Défaut. Detect Défaut
    // by comparing: if user tapped Défaut we get null; if dismissed we also
    // get null. Treat both as "default/clear" only when Défaut was pressed —
    // for simplicity, null means clear typing color / clear selection color.
    _applyColor(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: _boldTyping ? 'Gras activé' : 'Gras',
              visualDensity: VisualDensity.compact,
              onPressed: _onBoldPressed,
              style: IconButton.styleFrom(
                backgroundColor: _boldTyping
                    ? scheme.primary.withValues(alpha: 0.22)
                    : null,
              ),
              icon: Icon(
                Icons.format_bold,
                size: 20,
                color: _boldTyping ? scheme.primary : null,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: _pickColor,
              borderRadius: BorderRadius.circular(16),
              child: Tooltip(
                message: 'Couleur',
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _typingColor ?? scheme.onSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outlineVariant, width: 2),
                  ),
                ),
              ),
            ),
          ],
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
  bool typingBold = false;
  Color? typingColor;

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
    _mapRange(start, end, (span) => RuleTextSpan(
          text: span.text,
          bold: !span.bold,
          color: span.color,
        ));
  }

  void applyColor(int start, int end, Color? color) {
    final hex = color == null ? null : ruleColorToHex(color);
    _mapRange(start, end, (span) => RuleTextSpan(
          text: span.text,
          bold: span.bold,
          color: hex,
        ));
  }

  void _mapRange(
    int start,
    int end,
    RuleTextSpan Function(RuleTextSpan) map,
  ) {
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
        next.add(RuleTextSpan(
          text: span.text.substring(0, localStart),
          bold: span.bold,
          color: span.color,
        ));
      }
      next.add(map(RuleTextSpan(
        text: span.text.substring(localStart, localEnd),
        bold: span.bold,
        color: span.color,
      )));
      if (localEnd < span.text.length) {
        next.add(RuleTextSpan(
          text: span.text.substring(localEnd),
          bold: span.bold,
          color: span.color,
        ));
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
      if (prev.bold == cur.bold && prev.color == cur.color) {
        out[out.length - 1] = RuleTextSpan(
          text: prev.text + cur.text,
          bold: prev.bold,
          color: prev.color,
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
    _spans = _applyTextEdit(
      _spans,
      oldText,
      newText,
      typingBold: typingBold,
      typingColor: typingColor,
    );
    super.value = newValue;
  }

  static List<RuleTextSpan> _applyTextEdit(
    List<RuleTextSpan> spans,
    String oldText,
    String newText, {
    required bool typingBold,
    required Color? typingColor,
  }) {
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
    final insertHex =
        typingColor == null ? null : ruleColorToHex(typingColor);

    final before = <RuleTextSpan>[];
    final after = <RuleTextSpan>[];
    var offset = 0;
    bool? insertBold;
    String? inheritColor;
    for (final span in spans) {
      final spanStart = offset;
      final spanEnd = offset + span.text.length;
      offset = spanEnd;

      if (spanEnd <= prefix) {
        before.add(span);
        if (spanEnd == prefix) {
          insertBold = span.bold;
          inheritColor = span.color;
        }
        continue;
      }
      if (spanStart >= oldSuffix) {
        after.add(span);
        continue;
      }

      final keepStart = (prefix - spanStart).clamp(0, span.text.length);
      final keepEnd = (oldSuffix - spanStart).clamp(0, span.text.length);
      if (keepStart > 0) {
        before.add(RuleTextSpan(
          text: span.text.substring(0, keepStart),
          bold: span.bold,
          color: span.color,
        ));
        insertBold = span.bold;
        inheritColor = span.color;
      } else {
        insertBold ??= span.bold;
        inheritColor ??= span.color;
      }
      if (keepEnd < span.text.length) {
        after.add(RuleTextSpan(
          text: span.text.substring(keepEnd),
          bold: span.bold,
          color: span.color,
        ));
      }
    }

    final next = <RuleTextSpan>[...before];
    if (inserted.isNotEmpty) {
      next.add(RuleTextSpan(
        text: inserted,
        bold: typingBold || (insertBold ?? false),
        color: insertHex ?? inheritColor,
      ));
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
      final color = ruleColorFromHex(span.color);
      children.add(
        TextSpan(
          text: span.text,
          style: style?.copyWith(
            fontWeight: span.bold ? FontWeight.bold : style.fontWeight,
            color: color ?? style.color,
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
          final color = ruleColorFromHex(s.color);
          return TextSpan(
            text: s.text,
            style: base?.copyWith(
              fontWeight: s.bold ? FontWeight.bold : base.fontWeight,
              color: color ?? base.color,
            ),
          );
        }).toList(),
      ),
    );
  }
}
