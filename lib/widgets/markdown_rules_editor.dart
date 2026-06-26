import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Éditeur de règles : formatage visuel par défaut (aperçu WYSIWYG).
class MarkdownRulesEditor extends StatefulWidget {
  final TextEditingController controller;
  final int minLines;
  final String? hint;

  const MarkdownRulesEditor({
    super.key,
    required this.controller,
    this.minLines = 6,
    this.hint,
  });

  @override
  State<MarkdownRulesEditor> createState() => _MarkdownRulesEditorState();
}

class _MarkdownRulesEditorState extends State<MarkdownRulesEditor> {
  bool _preview = true;
  double _fontSize = 12;
  final _focusNode = FocusNode();
  TextSelection _lastSelection = const TextSelection.collapsed(offset: 0);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_trackSelection);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_trackSelection);
    _focusNode.dispose();
    super.dispose();
  }

  void _trackSelection() {
    final sel = widget.controller.selection;
    if (sel.isValid && sel.start >= 0) {
      _lastSelection = sel;
    }
  }

  TextSelection _effectiveSelection() {
    final sel = widget.controller.selection;
    if (sel.isValid && sel.start >= 0) return sel;
    return _lastSelection;
  }

  void _applyEdit(TextEditingValue value, {bool showPreview = true}) {
    widget.controller.value = value;
    _lastSelection = value.selection;
    setState(() => _preview = showPreview);
  }

  void _wrapSelection(String before, String after) {
    _focusNode.requestFocus();
    final text = widget.controller.text;
    final sel = _effectiveSelection();
    var start = sel.start.clamp(0, text.length);
    var end = sel.end.clamp(0, text.length);
    if (start > end) {
      final t = start;
      start = end;
      end = t;
    }
    final selected = text.substring(start, end);
    final insert = selected.isEmpty ? 'texte' : selected;
    final wrapped = '$before$insert$after';
    _applyEdit(
      TextEditingValue(
        text: text.replaceRange(start, end, wrapped),
        selection: TextSelection(
          baseOffset: start + before.length,
          extentOffset: start + before.length + insert.length,
        ),
      ),
    );
  }

  void _prefixLines(String prefix) {
    _focusNode.requestFocus();
    final text = widget.controller.text;
    final sel = _effectiveSelection();
    final start = sel.start.clamp(0, text.length);
    final lineStart = text.lastIndexOf('\n', start - 1) + 1;
    final lineEnd = text.indexOf('\n', start);
    final end = lineEnd == -1 ? text.length : lineEnd;
    final line = text.substring(lineStart, end);
    if (line.startsWith(prefix)) return;
    _applyEdit(
      TextEditingValue(
        text: text.replaceRange(lineStart, end, '$prefix$line'),
        selection: sel,
      ),
    );
  }

  void _insertSection(String title) {
    _focusNode.requestFocus();
    final block = '\n## $title\n\n';
    final text = widget.controller.text;
    final offset = _effectiveSelection().baseOffset.clamp(0, text.length);
    _applyEdit(
      TextEditingValue(
        text: text.replaceRange(offset, offset, block),
        selection: TextSelection.collapsed(offset: offset + block.length),
      ),
    );
  }

  MarkdownStyleSheet _styleSheet(ThemeData theme) {
    final base = theme.textTheme.bodyMedium?.copyWith(fontSize: _fontSize);
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      listBullet: base,
      h2: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: _fontSize + 2,
      ),
      strong: base?.copyWith(fontWeight: FontWeight.bold),
      em: base?.copyWith(fontStyle: FontStyle.italic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Gras',
              visualDensity: VisualDensity.compact,
              onPressed: () => _wrapSelection('**', '**'),
              icon: const Icon(Icons.format_bold, size: 20),
            ),
            IconButton(
              tooltip: 'Italique',
              visualDensity: VisualDensity.compact,
              onPressed: () => _wrapSelection('*', '*'),
              icon: const Icon(Icons.format_italic, size: 20),
            ),
            IconButton(
              tooltip: 'Liste',
              visualDensity: VisualDensity.compact,
              onPressed: () => _prefixLines('- '),
              icon: const Icon(Icons.format_list_bulleted, size: 20),
            ),
            PopupMenuButton<String>(
              tooltip: 'Section',
              icon: const Icon(Icons.title, size: 20),
              onSelected: _insertSection,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'Objectif', child: Text('Objectif')),
                PopupMenuItem(
                  value: 'Placement initial',
                  child: Text('Placement initial'),
                ),
                PopupMenuItem(
                  value: 'Règles résumées',
                  child: Text('Règles résumées'),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Text('Taille', style: theme.textTheme.labelSmall),
            DropdownButton<double>(
              value: _fontSize,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: const [9.0, 10.0, 11.0, 12.0, 13.0]
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text('${s.toInt()}'),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _fontSize = v);
              },
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(
                _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                size: 18,
              ),
              label: Text(_preview ? 'Texte brut' : 'Aperçu'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_preview)
          GestureDetector(
            onTap: () => setState(() => _preview = false),
            child: Container(
              constraints: BoxConstraints(minHeight: widget.minLines * 22.0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: MarkdownBody(
                data: widget.controller.text.isEmpty
                    ? '_Tape ici ou utilise « Texte brut » pour éditer_'
                    : widget.controller.text,
                styleSheet: _styleSheet(theme),
              ),
            ),
          )
        else
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            minLines: widget.minLines,
            maxLines: 12,
            onTap: _trackSelection,
            onChanged: (_) => _trackSelection(),
            decoration: InputDecoration(
              hintText: widget.hint ?? '## Objectif\n\n- Règle 1',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
      ],
    );
  }
}
