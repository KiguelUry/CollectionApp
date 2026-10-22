import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum BookOwnedRangeChoice { none, all, range }

class BookOwnedRangeResult {
  final BookOwnedRangeChoice choice;
  final int? from;
  final int? to;

  const BookOwnedRangeResult({
    required this.choice,
    this.from,
    this.to,
  });
}

/// « Quels tomes possèdes-tu déjà ? » à l'ajout d'une série entière.
Future<BookOwnedRangeResult?> showBookOwnedRangeDialog(
  BuildContext context, {
  required String seriesName,
  required int totalVolumes,
}) {
  return showDialog<BookOwnedRangeResult>(
    context: context,
    builder: (ctx) => _BookOwnedRangeDialog(
      seriesName: seriesName,
      totalVolumes: totalVolumes,
    ),
  );
}

class _BookOwnedRangeDialog extends StatefulWidget {
  final String seriesName;
  final int totalVolumes;

  const _BookOwnedRangeDialog({
    required this.seriesName,
    required this.totalVolumes,
  });

  @override
  State<_BookOwnedRangeDialog> createState() => _BookOwnedRangeDialogState();
}

class _BookOwnedRangeDialogState extends State<_BookOwnedRangeDialog> {
  BookOwnedRangeChoice _choice = BookOwnedRangeChoice.none;
  late final TextEditingController _from;
  late final TextEditingController _to;

  @override
  void initState() {
    super.initState();
    _from = TextEditingController(text: '1');
    _to = TextEditingController(text: '${widget.totalVolumes}');
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _submit() {
    if (_choice == BookOwnedRangeChoice.range) {
      final from = int.tryParse(_from.text.trim()) ?? 1;
      final to = int.tryParse(_to.text.trim()) ?? from;
      Navigator.pop(
        context,
        BookOwnedRangeResult(
          choice: BookOwnedRangeChoice.range,
          from: from,
          to: to,
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      BookOwnedRangeResult(choice: _choice),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quels tomes possèdes-tu déjà ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '« ${widget.seriesName} » · ${widget.totalVolumes} tomes',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            RadioListTile<BookOwnedRangeChoice>(
              value: BookOwnedRangeChoice.none,
              groupValue: _choice,
              title: const Text('Aucun'),
              dense: true,
              onChanged: (v) => setState(() => _choice = v!),
            ),
            RadioListTile<BookOwnedRangeChoice>(
              value: BookOwnedRangeChoice.all,
              groupValue: _choice,
              title: Text('Tous (1 → ${widget.totalVolumes})'),
              dense: true,
              onChanged: (v) => setState(() => _choice = v!),
            ),
            RadioListTile<BookOwnedRangeChoice>(
              value: BookOwnedRangeChoice.range,
              groupValue: _choice,
              title: const Text('Du tome X au tome Y'),
              dense: true,
              onChanged: (v) => setState(() => _choice = v!),
            ),
            if (_choice == BookOwnedRangeChoice.range) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _from,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(labelText: 'Du'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _to,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(labelText: 'Au'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continuer')),
      ],
    );
  }
}
