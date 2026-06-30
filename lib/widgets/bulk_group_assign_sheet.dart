import 'package:flutter/material.dart';

import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../services/item_group_service.dart';

/// Choisit un ou plusieurs groupes et y rattache plusieurs objets d'un coup.
Future<bool> showBulkGroupAssignSheet(
  BuildContext context, {
  required List<CollectionItem> items,
  required List<CollectionGroup> groups,
  Map<String, int> groupActivityCounts = const {},
}) async {
  if (items.isEmpty || groups.isEmpty) return false;

  final pickedIds = await showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BulkGroupPickSheet(
      itemCount: items.length,
      groups: groups,
      groupActivityCounts: groupActivityCounts,
    ),
  );
  if (pickedIds == null || pickedIds.isEmpty || !context.mounted) {
    return false;
  }

  final service = ItemGroupService();
  final namesById = {for (final g in groups) g.id: g.name};
  try {
    await service.bulkAddItemsToGroups(groupIds: pickedIds, items: items);
    if (context.mounted) {
      final groupLabel = pickedIds.length == 1
          ? '« ${namesById[pickedIds.first] ?? 'groupe'} »'
          : '${pickedIds.length} groupes';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${items.length} objet${items.length > 1 ? 's' : ''} '
            'ajouté${items.length > 1 ? 's' : ''} à $groupLabel',
          ),
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
    return false;
  }
}

/// Retire plusieurs objets d'un ou plusieurs groupes.
Future<bool> showBulkGroupRemoveSheet(
  BuildContext context, {
  required List<CollectionItem> items,
  required List<CollectionGroup> groups,
  Map<String, int> groupActivityCounts = const {},
}) async {
  if (items.isEmpty || groups.isEmpty) return false;

  final service = ItemGroupService();
  final memberGroupIds = await service.groupIdsForItems(items);
  final eligible = groups.where((g) => memberGroupIds.contains(g.id)).toList();
  if (eligible.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun des objets sélectionnés n\'est dans un groupe.'),
        ),
      );
    }
    return false;
  }

  final pickedIds = await showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BulkGroupPickSheet(
      itemCount: items.length,
      groups: eligible,
      groupActivityCounts: groupActivityCounts,
      removeMode: true,
    ),
  );
  if (pickedIds == null || pickedIds.isEmpty || !context.mounted) {
    return false;
  }

  final namesById = {for (final g in groups) g.id: g.name};
  try {
    await service.bulkRemoveItemsFromGroups(groupIds: pickedIds, items: items);
    if (context.mounted) {
      final groupLabel = pickedIds.length == 1
          ? '« ${namesById[pickedIds.first] ?? 'groupe'} »'
          : '${pickedIds.length} groupes';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${items.length} objet${items.length > 1 ? 's' : ''} '
            'retiré${items.length > 1 ? 's' : ''} de $groupLabel',
          ),
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
    return false;
  }
}

class _BulkGroupPickSheet extends StatefulWidget {
  final int itemCount;
  final List<CollectionGroup> groups;
  final Map<String, int> groupActivityCounts;
  final bool removeMode;

  const _BulkGroupPickSheet({
    required this.itemCount,
    required this.groups,
    required this.groupActivityCounts,
    this.removeMode = false,
  });

  @override
  State<_BulkGroupPickSheet> createState() => _BulkGroupPickSheetState();
}

class _BulkGroupPickSheetState extends State<_BulkGroupPickSheet> {
  final Set<String> _selected = {};

  List<CollectionGroup> get _sorted {
    final list = List<CollectionGroup>.from(widget.groups);
    list.sort((a, b) {
      final ca = widget.groupActivityCounts[a.id] ?? 0;
      final cb = widget.groupActivityCounts[b.id] ?? 0;
      final cmp = cb.compareTo(ca);
      return cmp != 0 ? cmp : a.name.compareTo(b.name);
    });
    return list;
  }

  void _toggle(String groupId, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(groupId);
      } else {
        _selected.remove(groupId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                widget.removeMode
                    ? 'Retirer ${widget.itemCount} objet'
                        '${widget.itemCount > 1 ? 's' : ''} du/des groupe(s)'
                    : 'Ajouter ${widget.itemCount} objet'
                        '${widget.itemCount > 1 ? 's' : ''} au(x) groupe(s)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                widget.removeMode
                    ? 'Coche les groupes à quitter'
                    : 'Coche un ou plusieurs groupes',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
                itemCount: _sorted.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final g = _sorted[index];
                  final count = widget.groupActivityCounts[g.id] ?? 0;
                  final checked = _selected.contains(g.id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (v) => _toggle(g.id, v),
                    secondary: Icon(
                      Icons.groups_outlined,
                      color: checked
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(g.name),
                    subtitle: count > 0
                        ? Text(
                            '$count jeu${count > 1 ? 'x' : ''} dans ce groupe',
                          )
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected.toList()),
                child: Text(
                  _selected.isEmpty
                      ? 'Choisir au moins un groupe'
                      : widget.removeMode
                          ? 'Retirer de ${_selected.length} groupe'
                              '${_selected.length > 1 ? 's' : ''}'
                          : 'Ajouter à ${_selected.length} groupe'
                              '${_selected.length > 1 ? 's' : ''}',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
