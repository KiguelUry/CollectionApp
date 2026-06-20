import 'package:flutter/material.dart';
import '../models/card_subcategory.dart';
import '../models/collection_list_filters.dart';
import '../models/item_tag.dart';
import '../models/storage_location.dart';
class GroupFilterOption {
  final String id;
  final String label;

  const GroupFilterOption({
    required this.id,
    required this.label,
  });
}

/// Barre recherche + filtres (emplacement, tags) + tri.
class CollectionFilterBar extends StatelessWidget {
  final CollectionListFilters filters;
  final ValueChanged<CollectionListFilters> onChanged;
  final List<StorageLocation> locations;
  final List<ItemTag> tags;
  final bool showFocusFilter;
  final bool showLocationFilter;
  final bool showTagFilter;
  final bool showBoardgameGenreFilter;
  final List<String> boardgameGenres;
  final bool showCardFilter;
  final bool showCardSubcategoryFilter;
  final bool showCardUniverseDetailFilters;
  final List<String> cardRarities;
  final List<String> pokemonTypes;
  final List<CardSubcategory> cardSubcategoryOptions;
  final List<GroupFilterOption> groupOptions;
  final TextEditingController? searchController;

  const CollectionFilterBar({
    super.key,
    required this.filters,
    required this.onChanged,
    this.searchController,
    this.locations = const [],
    this.tags = const [],
    this.showFocusFilter = true,
    this.showLocationFilter = true,
    this.showTagFilter = true,
    this.showBoardgameGenreFilter = false,
    this.boardgameGenres = const [],
    this.showCardFilter = false,
    this.showCardSubcategoryFilter = false,
    this.showCardUniverseDetailFilters = false,
    this.cardRarities = const [],
    this.pokemonTypes = const [],
    this.cardSubcategoryOptions = const [],
    this.groupOptions = const [],
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
                if (showFocusFilter)
                  _focusMenuButton(context),
                PopupMenuButton<CollectionSort>(
                  tooltip: 'Trier',
                  initialValue: filters.sort,
                  onSelected: (s) => onChanged(filters.copyWith(sort: s)),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: CollectionSort.titleAsc,
                      child: Text('Titre A → Z'),
                    ),
                    const PopupMenuItem(
                      value: CollectionSort.titleDesc,
                      child: Text('Titre Z → A'),
                    ),
                    const PopupMenuItem(
                      value: CollectionSort.newestFirst,
                      child: Text('Plus récents'),
                    ),
                    const PopupMenuItem(
                      value: CollectionSort.oldestFirst,
                      child: Text('Plus anciens'),
                    ),
                    const PopupMenuItem(
                      value: CollectionSort.ratingDesc,
                      child: Text('Mieux notés'),
                    ),
                    const PopupMenuItem(
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
                if (showBoardgameGenreFilter && boardgameGenres.isNotEmpty)
                  IconButton(
                    tooltip: 'Filtrer par genres',
                    onPressed: () => _openBoardgameGenreFilters(context),
                    icon: Badge(
                      isLabelVisible: filters.boardgameGenres.isNotEmpty,
                      label: Text('${filters.boardgameGenres.length}'),
                      child: Icon(
                        Icons.category_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                if (showCardFilter &&
                    (cardRarities.isNotEmpty ||
                        pokemonTypes.isNotEmpty ||
                        cardSubcategoryOptions.isNotEmpty))
                  IconButton(
                    tooltip: 'Filtres cartes',
                    onPressed: () => _openCardFilters(context),
                    icon: Badge(
                      isLabelVisible: filters.cardRarities.isNotEmpty ||
                          filters.pokemonTypes.isNotEmpty ||
                          filters.cardSubcategories.isNotEmpty,
                      label: Text(
                        '${filters.cardRarities.length + filters.pokemonTypes.length + filters.cardSubcategories.length}',
                      ),
                      child: Icon(
                        Icons.style_outlined,
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
            if (showCardSubcategoryFilter &&
                cardSubcategoryOptions.isNotEmpty) ...[
              const SizedBox(height: 8),
              _horizontalChips(
                height: 36,
                children: [
                  _cardSubcategoryChip(context, label: 'Tous les univers', id: null),
                  ...cardSubcategoryOptions.map(
                    (sub) => _cardSubcategoryChip(
                      context,
                      label: sub.label,
                      id: sub.dbValue,
                      color: sub.color,
                    ),
                  ),
                ],
              ),
            ],
            if (showCardUniverseDetailFilters) ...[
              if (cardRarities.isNotEmpty) ...[
                const SizedBox(height: 8),
                _horizontalChips(
                  height: 36,
                  children: [
                    _cardRarityChip(context, label: 'Toutes raretés', id: null),
                    for (final r in cardRarities)
                      _cardRarityChip(context, label: r, id: r),
                  ],
                ),
              ],
              if (pokemonTypes.isNotEmpty) ...[
                const SizedBox(height: 6),
                _horizontalChips(
                  height: 36,
                  children: [
                    _pokemonTypeChip(context, label: 'Tous types', id: null),
                    for (final t in pokemonTypes)
                      _pokemonTypeChip(context, label: t, id: t),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  bool get _focusIsActive =>
      filters.ownershipView != CollectionOwnershipView.all ||
      (filters.focusGroupId != null && filters.focusGroupId!.isNotEmpty);

  String get _focusTooltip {
    if (filters.ownershipView == CollectionOwnershipView.personal) {
      return 'Focus : moi uniquement';
    }
    if (filters.focusGroupId != null) {
      final name = groupOptions
          .where((g) => g.id == filters.focusGroupId)
          .map((g) => g.label)
          .firstOrNull;
      return 'Focus : ${name ?? 'groupe'}';
    }
    if (filters.ownershipView == CollectionOwnershipView.groups) {
      return 'Focus : groupes';
    }
    return 'Focus : tout afficher';
  }

  Widget _focusMenuButton(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: _focusTooltip,
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
          isLabelVisible: _focusIsActive,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(
            Icons.groups_outlined,
            size: 22,
            color: _focusIsActive
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade700,
          ),
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

  Widget _cardSubcategoryChip(
    BuildContext context, {
    required String label,
    required String? id,
    Color? color,
  }) {
    final selected = id == null
        ? filters.cardSubcategories.isEmpty
        : filters.cardSubcategories.contains(id);
    return _filterChip(
      label: label,
      selected: selected,
      onTap: () {
        if (id == null) {
          onChanged(
            filters.copyWith(
              cardSubcategories: {},
              clearCardFilters: true,
            ),
          );
          return;
        }
        final already = filters.cardSubcategories.length == 1 &&
            filters.cardSubcategories.contains(id);
        if (already) {
          onChanged(filters.copyWith(clearCardFilters: true));
        } else {
          onChanged(
            filters.copyWith(
              cardSubcategories: {id},
              cardRarities: {},
              pokemonTypes: {},
            ),
          );
        }
      },
      backgroundColor: color?.withValues(alpha: 0.15),
    );
  }

  Widget _cardRarityChip(
    BuildContext context, {
    required String label,
    required String? id,
  }) {
    final selected = id == null
        ? filters.cardRarities.isEmpty
        : filters.cardRarities.contains(id);
    return _filterChip(
      label: label,
      selected: selected,
      onTap: () {
        if (id == null) {
          onChanged(filters.copyWith(cardRarities: {}));
          return;
        }
        final next = Set<String>.from(filters.cardRarities);
        if (next.contains(id)) {
          next.remove(id);
        } else {
          next.add(id);
        }
        onChanged(filters.copyWith(cardRarities: next));
      },
    );
  }

  Widget _pokemonTypeChip(
    BuildContext context, {
    required String label,
    required String? id,
  }) {
    final selected = id == null
        ? filters.pokemonTypes.isEmpty
        : filters.pokemonTypes.contains(id);
    return _filterChip(
      label: label,
      selected: selected,
      onTap: () {
        if (id == null) {
          onChanged(filters.copyWith(pokemonTypes: {}));
          return;
        }
        final next = Set<String>.from(filters.pokemonTypes);
        if (next.contains(id)) {
          next.remove(id);
        } else {
          next.add(id);
        }
        onChanged(filters.copyWith(pokemonTypes: next));
      },
    );
  }

  Future<void> _openCardFilters(BuildContext context) async {
    final rarities = Set<String>.from(filters.cardRarities);
    final types = Set<String>.from(filters.pokemonTypes);
    final subs = Set<String>.from(filters.cardSubcategories);
    final result = await showDialog<
        ({Set<String> rarities, Set<String> types, Set<String> subs})>(
      context: context,
      builder: (ctx) {
        var tmpR = Set<String>.from(rarities);
        var tmpT = Set<String>.from(types);
        var tmpS = Set<String>.from(subs);
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('Filtres cartes'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cardRarities.isNotEmpty) ...[
                      Text(
                        'Rareté',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final r in cardRarities)
                            FilterChip(
                              label: Text(r),
                              selected: tmpR.contains(r),
                              onSelected: (on) => setStateDialog(() {
                                if (on) {
                                  tmpR.add(r);
                                } else {
                                  tmpR.remove(r);
                                }
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (pokemonTypes.isNotEmpty) ...[
                      Text(
                        'Type Pokémon',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in pokemonTypes)
                            FilterChip(
                              label: Text(t),
                              selected: tmpT.contains(t),
                              onSelected: (on) => setStateDialog(() {
                                if (on) {
                                  tmpT.add(t);
                                } else {
                                  tmpT.remove(t);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                    if (cardSubcategoryOptions.isNotEmpty) ...[
                      if (cardRarities.isNotEmpty || pokemonTypes.isNotEmpty)
                        const SizedBox(height: 12),
                      Text(
                        'Univers',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final sub in cardSubcategoryOptions)
                            FilterChip(
                              label: Text(sub.label),
                              selected: tmpS.contains(sub.dbValue),
                              onSelected: (on) => setStateDialog(() {
                                if (on) {
                                  tmpS.add(sub.dbValue);
                                } else {
                                  tmpS.remove(sub.dbValue);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  (rarities: <String>{}, types: <String>{}, subs: <String>{}),
                ),
                child: const Text('Effacer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  (rarities: tmpR, types: tmpT, subs: tmpS),
                ),
                child: const Text('Appliquer'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    onChanged(
      filters.copyWith(
        cardRarities: result.rarities,
        pokemonTypes: result.types,
        cardSubcategories: result.subs,
        clearCardFilters: result.rarities.isEmpty &&
            result.types.isEmpty &&
            result.subs.isEmpty,
      ),
    );
  }

  Future<void> _openBoardgameGenreFilters(BuildContext context) async {
    if (!showBoardgameGenreFilter || boardgameGenres.isEmpty) return;
    final current = Set<String>.from(filters.boardgameGenres);
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        final tmp = Set<String>.from(current);
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('Genres BGG'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final genre in boardgameGenres)
                      FilterChip(
                        label: Text(genre),
                        selected: tmp.contains(genre),
                        onSelected: (on) => setStateDialog(() {
                          if (on) {
                            tmp.add(genre);
                          } else {
                            tmp.remove(genre);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, <String>{}),
                child: const Text('Effacer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, tmp),
                child: const Text('Appliquer'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    onChanged(
      filters.copyWith(
        boardgameGenres: selected,
        clearBoardgameGenre: selected.isEmpty,
      ),
    );
  }

}
