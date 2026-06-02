import 'package:flutter/material.dart';
import '../models/lego_build_kind.dart';
import '../models/book_subcategory.dart';
import '../models/card_subcategory.dart';
import '../models/category_metadata.dart';
import '../models/collection_category.dart';
import 'category_metadata_fields.dart';

class AddItemManualDialog extends StatefulWidget {
  final String categoryLabel;
  final CollectionCategory category;
  final CardSubcategory? initialCardSubcategory;
  final MediaFormat? initialMediaFormat;
  final LegoBuildKind? initialLegoKind;
  final bool lockSubcategory;

  const AddItemManualDialog({
    super.key,
    required this.categoryLabel,
    required this.category,
    this.initialCardSubcategory,
    this.initialMediaFormat,
    this.initialLegoKind,
    this.lockSubcategory = false,
  });

  @override
  State<AddItemManualDialog> createState() => _AddItemManualDialogState();
}

class _AddItemManualDialogState extends State<AddItemManualDialog> {
  final _titleController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _metadataKey = GlobalKey<CategoryMetadataFieldsState>();
  BookSubcategory _bookSubcategory = BookSubcategory.other;

  @override
  void dispose() {
    _titleController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMetadata = widget.category.usesMetadataForm;

    return AlertDialog(
      title: Text('Ajouter — ${widget.categoryLabel}'),
      content: SizedBox(
        width: double.maxFinite,
        height: hasMetadata ? 520 : null,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              if (hasMetadata) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                CategoryMetadataFields(
                  key: _metadataKey,
                  category: widget.category,
                  initialCardSubcategory: widget.initialCardSubcategory,
                  initialMediaFormat: widget.initialMediaFormat,
                  initialLegoKind: widget.initialLegoKind,
                  lockCardSubcategory: widget.lockSubcategory &&
                      widget.category == CollectionCategory.card,
                  lockMediaFormat: widget.lockSubcategory &&
                      widget.category == CollectionCategory.media,
                  lockLegoKind: widget.lockSubcategory &&
                      widget.category == CollectionCategory.lego,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Continuer'),
        ),
      ],
    );
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    String? subcategory;
    Map<String, dynamic>? metadata;

    if (widget.category == CollectionCategory.book) {
      subcategory = _bookSubcategory.dbValue;
    } else if (widget.category.usesMetadataForm) {
      final metaState = _metadataKey.currentState;
      subcategory = metaState?.subcategory;
      metadata = metaState?.buildMetadata();
    }

    Navigator.pop(context, {
      'title': title,
      'image_url': _imageUrlController.text.trim().isEmpty
          ? null
          : _imageUrlController.text.trim(),
      if (subcategory != null) 'subcategory': subcategory,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    });
  }
}
