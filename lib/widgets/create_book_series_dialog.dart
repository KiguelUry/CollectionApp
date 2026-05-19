import 'package:flutter/material.dart';

import '../models/book_subcategory.dart';

class CreateBookSeriesResult {
  final String name;
  final int? expectedVolumes;

  const CreateBookSeriesResult({
    required this.name,
    this.expectedVolumes,
  });
}

Future<CreateBookSeriesResult?> showCreateBookSeriesDialog(
  BuildContext context, {
  required BookSubcategory subcategory,
  String? parentName,
}) {
  return showDialog<CreateBookSeriesResult>(
    context: context,
    builder: (ctx) => _CreateBookSeriesDialog(
      subcategory: subcategory,
      parentName: parentName,
    ),
  );
}

class _CreateBookSeriesDialog extends StatefulWidget {
  final BookSubcategory subcategory;
  final String? parentName;

  const _CreateBookSeriesDialog({
    required this.subcategory,
    this.parentName,
  });

  @override
  State<_CreateBookSeriesDialog> createState() => _CreateBookSeriesDialogState();
}

class _CreateBookSeriesDialogState extends State<_CreateBookSeriesDialog> {
  final _name = TextEditingController();
  final _count = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subcategory.label;
    return AlertDialog(
      title: Text(
        widget.parentName != null
            ? 'Sous-série · ${widget.parentName}'
            : 'Nouvelle série · $sub',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nom de la série',
              hintText: 'Naruto, Thorgal…',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _count,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nombre de tomes (optionnel)',
              hintText: '42',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final count = int.tryParse(_count.text.trim());
            Navigator.pop(
              context,
              CreateBookSeriesResult(
                name: name,
                expectedVolumes: count != null && count > 0 ? count : null,
              ),
            );
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
