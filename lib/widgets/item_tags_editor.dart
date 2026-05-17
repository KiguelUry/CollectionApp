import 'package:flutter/material.dart';
import '../models/item_tag.dart';
import '../services/tag_service.dart';

/// Éditeur de tags sur la fiche objet.
class ItemTagsEditor extends StatefulWidget {
  final String itemId;
  final List<ItemTag> initialTags;
  final bool readOnly;

  const ItemTagsEditor({
    super.key,
    required this.itemId,
    required this.initialTags,
    this.readOnly = false,
  });

  @override
  State<ItemTagsEditor> createState() => _ItemTagsEditorState();
}

class _ItemTagsEditorState extends State<ItemTagsEditor> {
  final _tagService = TagService();
  late Set<String> _selectedIds;
  List<ItemTag> _allTags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.initialTags.map((t) => t.id).toSet();
    _load();
  }

  Future<void> _load() async {
    try {
      _allTags = await _tagService.fetchMyTags();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist() async {
    await _tagService.setItemTags(widget.itemId, _selectedIds.toList());
  }

  Future<void> _createTag() async {
    final controller = TextEditingController();
    final created = await showDialog<ItemTag>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau tag'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nom',
            hintText: 'ex. Famille, Noël, Rare',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final tag = await _tagService.createTag(controller.text);
                if (ctx.mounted) Navigator.pop(ctx, tag);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$e')),
                  );
                }
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (created == null) return;
    setState(() {
      _allTags = [..._allTags, created]..sort((a, b) => a.label.compareTo(b.label));
      _selectedIds.add(created.id);
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    if (widget.readOnly) {
      if (widget.initialTags.isEmpty) {
        return Text(
          'Aucun tag',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        );
      }
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: widget.initialTags
            .map(
              (t) => Chip(
                label: Text(t.label),
                backgroundColor: t.color.withValues(alpha: 0.2),
              ),
            )
            .toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ..._allTags.map((tag) {
              final selected = _selectedIds.contains(tag.id);
              return FilterChip(
                label: Text(tag.label),
                selected: selected,
                onSelected: (v) async {
                  setState(() {
                    if (v) {
                      _selectedIds.add(tag.id);
                    } else {
                      _selectedIds.remove(tag.id);
                    }
                  });
                  await _persist();
                },
                backgroundColor: tag.color.withValues(alpha: 0.12),
                showCheckmark: true,
              );
            }),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Tag'),
              onPressed: _createTag,
            ),
          ],
        ),
        if (_allTags.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Crée des tags pour classer tes objets (ex. « Rare », « À compléter »).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }
}
