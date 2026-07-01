import 'package:flutter/material.dart';

import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../services/item_group_service.dart';

/// Gère l'appartenance aux groupes (cocher = ajouter, décocher = retirer).
Future<bool> showBulkGroupManageSheet(
  BuildContext context, {
  required List<CollectionItem> items,
  required List<CollectionGroup> groups,
  Map<String, int> groupActivityCounts = const {},
}) async {
  if (items.isEmpty || groups.isEmpty) return false;

  final service = ItemGroupService();
  final membership = await service.fetchMembershipMap(
    items.map((i) => i.id).toList(),
  );
  if (!context.mounted) return false;

  final result = await showModalBottomSheet<_BulkGroupManageResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BulkGroupManageSheet(
      items: items,
      groups: groups,
      membership: membership,
      groupActivityCounts: groupActivityCounts,
    ),
  );
  if (result == null || !context.mounted) return false;
  if (!result.hasChanges) return false;

  try {
    await service.bulkApplyGroupMembershipChanges(
      items: items,
      addGroupIds: result.addTo,
      removeGroupIds: result.removeFrom,
    );
    if (context.mounted) {
      final parts = <String>[];
      if (result.addTo.isNotEmpty) {
        parts.add(
          'ajouté${items.length > 1 ? 's' : ''} à '
          '${result.addTo.length} groupe${result.addTo.length > 1 ? 's' : ''}',
        );
      }
      if (result.removeFrom.isNotEmpty) {
        parts.add(
          'retiré${items.length > 1 ? 's' : ''} de '
          '${result.removeFrom.length} groupe${result.removeFrom.length > 1 ? 's' : ''}',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${items.length} objet${items.length > 1 ? 's' : ''} ${parts.join(' et ')}',
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

@Deprecated('Utiliser showBulkGroupManageSheet')
Future<bool> showBulkGroupAssignSheet(
  BuildContext context, {
  required List<CollectionItem> items,
  required List<CollectionGroup> groups,
  Map<String, int> groupActivityCounts = const {},
}) =>
    showBulkGroupManageSheet(
      context,
      items: items,
      groups: groups,
      groupActivityCounts: groupActivityCounts,
    );

@Deprecated('Utiliser showBulkGroupManageSheet')
Future<bool> showBulkGroupRemoveSheet(
  BuildContext context, {
  required List<CollectionItem> items,
  required List<CollectionGroup> groups,
  Map<String, int> groupActivityCounts = const {},
}) =>
    showBulkGroupManageSheet(
      context,
      items: items,
      groups: groups,
      groupActivityCounts: groupActivityCounts,
    );

class _BulkGroupManageResult {
  final Set<String> addTo;
  final Set<String> removeFrom;

  const _BulkGroupManageResult({
    required this.addTo,
    required this.removeFrom,
  });

  bool get hasChanges => addTo.isNotEmpty || removeFrom.isNotEmpty;
}

class _BulkGroupManageSheet extends StatefulWidget {
  final List<CollectionItem> items;
  final List<CollectionGroup> groups;
  final Map<String, Set<String>> membership;
  final Map<String, int> groupActivityCounts;

  const _BulkGroupManageSheet({
    required this.items,
    required this.groups,
    required this.membership,
    required this.groupActivityCounts,
  });

  @override
  State<_BulkGroupManageSheet> createState() => _BulkGroupManageSheetState();
}

class _BulkGroupManageSheetState extends State<_BulkGroupManageSheet> {
  late final Map<String, bool?> _initial;
  late final Map<String, bool?> _state;

  @override
  void initState() {
    super.initState();
    _initial = {
      for (final g in widget.groups) g.id: _membershipState(g.id),
    };
    _state = Map<String, bool?>.from(_initial);
  }

  bool? _membershipState(String groupId) {
    var inCount = 0;
    for (final item in widget.items) {
      if (widget.membership[item.id]?.contains(groupId) ?? false) {
        inCount++;
      }
    }
    if (inCount == 0) return false;
    if (inCount == widget.items.length) return true;
    return null;
  }

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

  void _toggle(String groupId) {
    setState(() {
      final current = _state[groupId];
      if (current == true) {
        _state[groupId] = false;
      } else {
        _state[groupId] = true;
      }
    });
  }

  _BulkGroupManageResult _buildResult() {
    final addTo = <String>{};
    final removeFrom = <String>{};
    for (final entry in _state.entries) {
      final initial = _initial[entry.key];
      final desired = entry.value;
      if (desired == initial) continue;
      if (desired == true) addTo.add(entry.key);
      if (desired == false) removeFrom.add(entry.key);
    }
    return _BulkGroupManageResult(addTo: addTo, removeFrom: removeFrom);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    final result = _buildResult();
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
                'Groupes — $count objet${count > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Coche pour ajouter au groupe, décoche pour retirer',
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
                  final value = _state[g.id];
                  return CheckboxListTile(
                    tristate: true,
                    value: value,
                    onChanged: (_) => _toggle(g.id),
                    secondary: Icon(
                      Icons.groups_outlined,
                      color: value == true
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
                onPressed: result.hasChanges
                    ? () => Navigator.pop(context, result)
                    : null,
                child: Text(
                  result.hasChanges
                      ? 'Appliquer'
                      : 'Modifier au moins un groupe',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
