import 'package:flutter/material.dart';
import '../models/collection_list_filters.dart';
import '../models/item_tag.dart';
import '../models/storage_location.dart';
import '../utils/holder_filter.dart';

/// Barre recherche + filtres (emplacement, tags) + tri.
class CollectionFilterBar extends StatelessWidget {
  final CollectionListFilters filters;
  final ValueChanged<CollectionListFilters> onChanged;
  final List<StorageLocation> locations;
  final List<ItemTag> tags;
  final List<HolderFilterOption> holderOptions;
  final bool showScopeFilters;
  final bool showStatusFilters;
  final bool showLocationFilter;
  final bool showHolderFilter;
  final bool showTagFilter;
  final bool showHighlyRatedFilter;
  final VoidCallback? onShakePick;
  final TextEditingController? searchController;

  const CollectionFilterBar({
    super.key,
    required this.filters,
    required this.onChanged,
    this.searchController,
    this.locations = const [],
    this.tags = const [],
    this.holderOptions = const [],
    this.showScopeFilters = true,
    this.showStatusFilters = true,
    this.showLocationFilter = true,
    this.showHolderFilter = false,
    this.showTagFilter = true,
    this.showHighlyRatedFilter = true,
    this.onShakePick,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Rechercher…',
                      prefixIcon: const Icon(Icons.search, size: 22),
                      suffixIcon: filters.searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                searchController?.clear();
                                onChanged(filters.copyWith(searchQuery: ''));
                              },
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (v) =>
                        onChanged(filters.copyWith(searchQuery: v)),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<CollectionSort>(
                  tooltip: 'Trier',
                  initialValue: filters.sort,
                  onSelected: (s) => onChanged(filters.copyWith(sort: s)),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: CollectionSort.titleAsc,
                      child: Text('Titre A → Z'),
                    ),
                    PopupMenuItem(
                      value: CollectionSort.titleDesc,
                      child: Text('Titre Z → A'),
                    ),
                    PopupMenuItem(
                      value: CollectionSort.newestFirst,
                      child: Text('Plus récents'),
                    ),
                    PopupMenuItem(
                      value: CollectionSort.oldestFirst,
                      child: Text('Plus anciens'),
                    ),
                    PopupMenuItem(
                      value: CollectionSort.ratingDesc,
                      child: Text('Mieux notés'),
                    ),
                    PopupMenuItem(
                      value: CollectionSort.quantityDesc,
                      child: Text('Quantité'),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.sort,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (filters.hasActiveFilters)
                  IconButton(
                    tooltip: 'Réinitialiser',
                    onPressed: () => onChanged(CollectionListFilters()),
                    icon: const Icon(Icons.filter_alt_off, size: 22),
                  ),
              ],
            ),
            if (showHolderFilter) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _holderFilterChip(context)),
                  if (onShakePick != null)
                    IconButton(
                      tooltip: 'À quoi on joue ce soir ?',
                      onPressed: onShakePick,
                      icon: Icon(
                        Icons.casino_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ],
            if (showLocationFilter && locations.isNotEmpty) ...[
              const SizedBox(height: 8),
              _horizontalChips(
                children: [
                  _locationChip(context, label: 'Tous les lieux', id: null),
                  ...locations.map(
                    (loc) =>
                        _locationChip(context, label: loc.label, id: loc.id),
                  ),
                ],
              ),
            ],
            if (showTagFilter && tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              _horizontalChips(
                height: 36,
                children: [
                  _tagChip(context, label: 'Tous tags', id: null),
                  ...tags.map(
                    (t) => _tagChip(
                      context,
                      label: t.label,
                      id: t.id,
                      color: t.color,
                    ),
                  ),
                ],
              ),
            ],
            if (showScopeFilters ||
                (showStatusFilters && showHighlyRatedFilter)) ...[
              const SizedBox(height: 8),
              _horizontalChips(
                children: [
                  if (showScopeFilters) ...[
                    _chip(
                      label: 'Tout',
                      selected: filters.scope == CollectionScopeFilter.all,
                      onTap: () => onChanged(
                        filters.copyWith(scope: CollectionScopeFilter.all),
                      ),
                    ),
                    _chip(
                      label: 'Perso',
                      icon: Icons.person_outline,
                      selected:
                          filters.scope == CollectionScopeFilter.personalOnly,
                      onTap: () => onChanged(
                        filters.copyWith(
                          scope: CollectionScopeFilter.personalOnly,
                        ),
                      ),
                    ),
                    _chip(
                      label: 'Groupe',
                      icon: Icons.groups,
                      selected:
                          filters.scope == CollectionScopeFilter.groupOnly,
                      onTap: () => onChanged(
                        filters.copyWith(
                          scope: CollectionScopeFilter.groupOnly,
                        ),
                      ),
                    ),
                    _chip(
                      label: 'Prêté',
                      icon: Icons.handshake_outlined,
                      selected:
                          filters.scope == CollectionScopeFilter.onLoanOnly,
                      onTap: () => onChanged(
                        filters.copyWith(
                          scope: CollectionScopeFilter.onLoanOnly,
                        ),
                      ),
                    ),
                  ],
                  if (showStatusFilters && showHighlyRatedFilter)
                    _chip(
                      label: '★ 4+',
                      selected: filters.status ==
                          CollectionStatusFilter.highlyRated,
                      onTap: () => onChanged(
                        filters.copyWith(
                          status: filters.status ==
                                  CollectionStatusFilter.highlyRated
                              ? CollectionStatusFilter.all
                              : CollectionStatusFilter.highlyRated,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _horizontalChips({
    required List<Widget> children,
    double height = 40,
  }) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? backgroundColor,
  }) {
    return FilterChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      avatar: icon != null
          ? Icon(icon, size: 16, color: selected ? null : Colors.grey.shade700)
          : null,
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      backgroundColor: backgroundColor,
    );
  }

  Widget _holderFilterChip(BuildContext context) {
    HolderFilterOption? selected;
    if (filters.holderKey != null) {
      for (final o in holderOptions) {
        if (o.key == filters.holderKey) {
          selected = o;
          break;
        }
      }
    }
    final label = selected == null
        ? 'Chez qui : tous'
        : '${selected.label} (${selected.count})';

    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String?>(
        tooltip: 'Filtrer par chez qui',
        onSelected: (key) => onChanged(
          filters.copyWith(holderKey: key, clearHolder: key == null),
        ),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: null,
            child: Text('Tous'),
          ),
          ...holderOptions.map(
            (o) => PopupMenuItem(
              value: o.key,
              child: Text('${o.label} (${o.count})'),
            ),
          ),
        ],
        child: Chip(
          avatar: Icon(
            selected == null ? Icons.place_outlined : Icons.person_pin,
            size: 18,
          ),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          deleteIcon: selected != null
              ? const Icon(Icons.close, size: 16)
              : null,
          onDeleted: selected != null
              ? () => onChanged(filters.copyWith(clearHolder: true))
              : null,
        ),
      ),
    );
  }

  Widget _locationChip(
    BuildContext context, {
    required String label,
    required String? id,
  }) {
    final selected = filters.locationId == id;
    return _filterChip(
      label: label,
      selected: selected,
      onTap: () => onChanged(
        filters.copyWith(
          locationId: id,
          clearLocation: id == null,
        ),
      ),
    );
  }

  Widget _tagChip(
    BuildContext context, {
    required String label,
    required String? id,
    Color? color,
  }) {
    final selected = filters.tagId == id;
    return _filterChip(
      label: label,
      selected: selected,
      onTap: () => onChanged(
        filters.copyWith(tagId: id, clearTag: id == null),
      ),
      backgroundColor: color?.withValues(alpha: 0.15),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return _filterChip(
      label: label,
      selected: selected,
      onTap: onTap,
      icon: icon,
    );
  }
}
