import 'package:flutter/material.dart';

class AddItemManualDialog extends StatefulWidget {
  final String categoryLabel;

  const AddItemManualDialog({super.key, required this.categoryLabel});

  @override
  State<AddItemManualDialog> createState() => _AddItemManualDialogState();
}

class _AddItemManualDialogState extends State<AddItemManualDialog> {
  final _titleController = TextEditingController();
  final _imageUrlController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ajouter — ${widget.categoryLabel}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Titre'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _imageUrlController,
            decoration: const InputDecoration(
              labelText: 'URL image (optionnel)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(context, {
              'title': title,
              'image_url': _imageUrlController.text.trim().isEmpty
                  ? null
                  : _imageUrlController.text.trim(),
            });
          },
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}
