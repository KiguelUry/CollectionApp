import 'package:flutter/material.dart';

import '../models/user_collection_type.dart';
import '../services/user_collection_type_service.dart';

Future<UserCollectionType?> showCreateCustomCollectionDialog(
  BuildContext context,
) {
  return showDialog<UserCollectionType>(
    context: context,
    builder: (ctx) => const _CreateCustomCollectionDialog(),
  );
}

class _CreateCustomCollectionDialog extends StatefulWidget {
  const _CreateCustomCollectionDialog();

  @override
  State<_CreateCustomCollectionDialog> createState() =>
      _CreateCustomCollectionDialogState();
}

class _CreateCustomCollectionDialogState
    extends State<_CreateCustomCollectionDialog> {
  final _nameController = TextEditingController();
  String _iconKey = 'category';
  Color _color = UserCollectionType.colorChoices.first;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    final created = await UserCollectionTypeService().create(
      UserCollectionType(
        id: '',
        name: name,
        iconKey: _iconKey,
        color: _color,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (created != null) {
      Navigator.pop(context, created);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible de créer la collection. '
            'As-tu exécuté supabase/schema_user_collection_types.sql ?',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle collection'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  hintText: 'Figurines, Vin, Sneakers…',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              const Text('Icône', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (key, label) in UserCollectionType.iconChoices)
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 11)),
                      avatar: Icon(UserCollectionType.iconFromKey(key), size: 18),
                      selected: _iconKey == key,
                      onSelected: (_) => setState(() => _iconKey = key),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Couleur', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in UserCollectionType.colorChoices)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == c ? Colors.black : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Créer'),
        ),
      ],
    );
  }
}
