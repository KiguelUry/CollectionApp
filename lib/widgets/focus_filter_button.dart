import 'package:flutter/material.dart';

import '../models/collection_list_filters.dart';
import 'collection_filter_bar.dart' show GroupFilterOption;

/// Menu 👥 Focus : Tout / Moi / par groupe.
class FocusFilterButton extends StatelessWidget {
  final CollectionListFilters filters;
  final ValueChanged<CollectionListFilters> onChanged;
  final List<GroupFilterOption> groupOptions;
  final Color? activeColor;

  const FocusFilterButton({
    super.key,
    required this.filters,
    required this.onChanged,
    this.groupOptions = const [],
    this.activeColor,
  });

  bool get _isActive =>
      filters.ownershipView != CollectionOwnershipView.all ||
      filters.focusGroupId != null;

  @override
  Widget build(BuildContext context) {
    final accent = activeColor ?? Theme.of(context).colorScheme.primary;
    return PopupMenuButton<String>(
      tooltip: 'Focus collection',
      onSelected: (value) {
        if (value == '__all__') {
          onChanged(
            filters.copyWith(
              ownershipView: CollectionOwnershipView.all,
              clearFocusGroup: true,
              clearGroups: true,
            ),
          );
        } else if (value == '__personal__') {
          onChanged(
            filters.copyWith(
              ownershipView: CollectionOwnershipView.personal,
              clearFocusGroup: true,
              clearGroups: true,
            ),
          );
        } else {
          onChanged(
            filters.copyWith(
              ownershipView: CollectionOwnershipView.groups,
              focusGroupId: value,
              groupIds: {value},
            ),
          );
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: '__all__',
          checked: filters.ownershipView == CollectionOwnershipView.all,
          child: const Text('Tout afficher'),
        ),
        CheckedPopupMenuItem(
          value: '__personal__',
          checked: filters.ownershipView == CollectionOwnershipView.personal,
          child: const Text('Moi uniquement'),
        ),
        if (groupOptions.isNotEmpty) const PopupMenuDivider(),
        ...groupOptions.map(
          (g) => CheckedPopupMenuItem(
            value: g.id,
            checked: filters.focusGroupId == g.id,
            child: Text(g.label),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Badge(
          isLabelVisible: _isActive,
          backgroundColor: accent,
          child: Icon(
            Icons.groups_outlined,
            size: 22,
            color: _isActive ? accent : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
