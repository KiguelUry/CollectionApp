import 'package:flutter/material.dart';

import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../models/item_condition.dart';
import '../utils/item_copy_units.dart';
import 'compact_whereabouts_dropdown.dart';
import 'detail_bento_tile.dart';

enum ItemCopyUnitsMode { whereabouts, value }

/// Sous-bentos par exemplaire (localisation ou valeur/état).
class ItemCopyUnitsPanel extends StatelessWidget {
  final CollectionItem item;
  final List<CollectionGroup> groups;
  final Set<String> selectedGroupIds;
  final bool readOnly;
  final ItemCopyUnitsMode mode;
  final ValueChanged<CollectionItem> onItemChanged;

  const ItemCopyUnitsPanel({
    super.key,
    required this.item,
    required this.groups,
    required this.selectedGroupIds,
    required this.readOnly,
    required this.mode,
    required this.onItemChanged,
  });

  @override
  Widget build(BuildContext context) {
    final units = readCopyUnits(item);
    if (units.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < units.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _CopyUnitTile(
            unit: units[i],
            readOnly: readOnly,
            mode: mode,
            groups: groups,
            selectedGroupIds: selectedGroupIds,
            onChanged: (updated) {
              final next = List<ItemCopyUnit>.from(units);
              next[i] = updated;
              onItemChanged(
                mode == ItemCopyUnitsMode.whereabouts
                    ? itemWithCopyUnitsAndGroups(
                        item,
                        next,
                        groupName: (id) {
                          for (final g in groups) {
                            if (g.id == id) return g.name;
                          }
                          return null;
                        },
                      )
                    : itemWithCopyUnits(item, next),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _CopyUnitTile extends StatefulWidget {
  final ItemCopyUnit unit;
  final bool readOnly;
  final ItemCopyUnitsMode mode;
  final List<CollectionGroup> groups;
  final Set<String> selectedGroupIds;
  final ValueChanged<ItemCopyUnit> onChanged;

  const _CopyUnitTile({
    required this.unit,
    required this.readOnly,
    required this.mode,
    required this.groups,
    required this.selectedGroupIds,
    required this.onChanged,
  });

  @override
  State<_CopyUnitTile> createState() => _CopyUnitTileState();
}

class _CopyUnitTileState extends State<_CopyUnitTile> {
  bool _open = false;
  late TextEditingController _labelController;
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.unit.label ?? '');
    _priceController = TextEditingController(
      text: widget.unit.purchasePrice?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _CopyUnitTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unit.label != widget.unit.label) {
      _labelController.text = widget.unit.label ?? '';
    }
    if (oldWidget.unit.purchasePrice != widget.unit.purchasePrice) {
      _priceController.text =
          widget.unit.purchasePrice?.toStringAsFixed(2) ?? '';
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  String get _title => widget.unit.defaultLabel(widget.unit.index + 1);

  String get _subtitle {
    if (widget.mode == ItemCopyUnitsMode.whereabouts) {
      final where = holderLabelForCopyUnit(widget.unit);
      final names = [
        for (final g in widget.groups)
          if (widget.unit.groupIds.contains(g.id)) g.name,
      ];
      if (names.isEmpty) return where;
      return '$where · ${names.join(', ')}';
    }
    final parts = <String>[];
    if (widget.unit.purchasePrice != null) {
      parts.add('${widget.unit.purchasePrice!.toStringAsFixed(0)} €');
    }
    final c = widget.unit.condition?.label;
    if (c != null) parts.add(c);
    return parts.isEmpty ? 'Non renseigné' : parts.join(' · ');
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _labelController.text);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nom de l\'exemplaire'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              hintText: 'ex. Jeu chez Kiki',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (name == null || !mounted) return;
      _labelController.text = name;
      widget.onChanged(widget.unit.copyWith(label: name));
    } finally {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DetailBentoSubTile(
                icon: widget.mode == ItemCopyUnitsMode.whereabouts
                    ? Icons.place_outlined
                    : Icons.inventory_2_outlined,
                title: _title,
                subtitle: _subtitle,
                accent: accent,
                selected: _open,
                onTap: () => setState(() => _open = !_open),
              ),
            ),
            if (!widget.readOnly)
              IconButton(
                tooltip: 'Renommer',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: _rename,
              ),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.mode == ItemCopyUnitsMode.whereabouts) ...[
                  if (widget.groups.isNotEmpty) ...[
                    Text(
                      'Partagé avec',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final g in widget.groups)
                          FilterChip(
                            label: Text(g.name),
                            visualDensity: VisualDensity.compact,
                            selected: widget.unit.groupIds.contains(g.id),
                            onSelected: widget.readOnly
                                ? null
                                : (on) {
                                    final ids = {...widget.unit.groupIds};
                                    on ? ids.add(g.id) : ids.remove(g.id);
                                    widget.onChanged(
                                      widget.unit.copyWith(
                                        groupIds: ids.toList(),
                                      ),
                                    );
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  CompactWhereaboutsDropdown(
                    groups: widget.groups,
                    selectedGroupIds: widget.unit.groupIds.isEmpty
                        ? widget.selectedGroupIds
                        : widget.unit.groupIds.toSet(),
                    locationUserId: widget.unit.locationUserId,
                    holderLabel:
                        widget.unit.locationLabel ?? widget.unit.holderLabel,
                    readOnly: widget.readOnly,
                    applyDefaultIfEmpty: false,
                    onChanged: ({
                      locationUserId,
                      holderLabel,
                      clearHolder = false,
                      manualHolder = false,
                    }) {
                      if (clearHolder) {
                        widget.onChanged(
                          widget.unit.copyWith(
                            clearLocationUserId: true,
                            clearHolder: true,
                          ),
                        );
                        return;
                      }
                      if (manualHolder) {
                        widget.onChanged(
                          widget.unit.copyWith(
                            clearLocationUserId: true,
                            holderLabel: holderLabel,
                            locationLabel: holderLabel,
                          ),
                        );
                        return;
                      }
                      widget.onChanged(
                        widget.unit.copyWith(
                          locationUserId: locationUserId,
                          locationLabel: holderLabel,
                          clearHolder: true,
                        ),
                      );
                    },
                  ),
                ] else ...[
                  TextField(
                    controller: _priceController,
                    readOnly: widget.readOnly,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Prix d\'achat (€)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: widget.readOnly
                        ? null
                        : (v) {
                            final p = double.tryParse(v.replaceAll(',', '.'));
                            widget.onChanged(
                              widget.unit.copyWith(
                                purchasePrice: p,
                                clearPrice: p == null,
                              ),
                            );
                          },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ItemCondition?>(
                    initialValue: widget.unit.condition,
                    decoration: const InputDecoration(
                      labelText: 'État',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<ItemCondition?>(
                        value: null,
                        child: Text('— Non renseigné —'),
                      ),
                      ...ItemCondition.values.map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.label),
                        ),
                      ),
                    ],
                    onChanged: widget.readOnly
                        ? null
                        : (val) {
                            widget.onChanged(
                              widget.unit.copyWith(
                                condition: val,
                                clearCondition: val == null,
                              ),
                            );
                          },
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
