import 'package:flutter/material.dart';
import '../models/book_subcategory.dart';
import '../models/collection_category.dart';

class AddItemManualDialog extends StatefulWidget {
  final String categoryLabel;
  final CollectionCategory category;

  const AddItemManualDialog({
    super.key,
    required this.categoryLabel,
    required this.category,
  });

  @override
  State<AddItemManualDialog> createState() => _AddItemManualDialogState();
}

class _AddItemManualDialogState extends State<AddItemManualDialog> {
  final _titleController = TextEditingController();
  final _imageUrlController = TextEditingController();
  BookSubcategory _bookSubcategory = BookSubcategory.other;

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
          if (widget.category == CollectionCategory.book) ...[
            DropdownButtonFormField<BookSubcategory>(
              initialValue: _bookSubcategory,
              decoration: const InputDecoration(labelText: 'Type de livre'),
              items: BookSubcategory.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.label),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _bookSubcategory = val);
              },
            ),
            const SizedBox(height: 12),
          ],
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
              if (widget.category == CollectionCategory.book)
                'subcategory': _bookSubcategory.dbValue,
            });
          },
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}
