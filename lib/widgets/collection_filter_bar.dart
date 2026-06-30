import 'package:flutter/material.dart';
import '../models/card_subcategory.dart';
import '../models/collection_list_filters.dart';
import '../models/item_tag.dart';
import '../models/storage_location.dart';
import '../utils/holder_filter.dart';
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
  final List<HolderFilterOption> holderFilterOptions;
  final bool useHolderLocationFilter;
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
    this.holderFilterOptions = const [],
    this.useHolderLocationFilter = false,
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
                _sortMenuButton(context),
                const SizedBox(width: 4),
                _filterMenuButton(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortMenuButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sortActive = filters.sort != CollectionSort.titleAsc;
    return PopupMenuButton<CollectionSort>(
      tooltip: 'Trier',
      initialValue: filters.sort,
      onSelected: (s) {
        if (s == CollectionSort.ratingDesc &&
            filters.sort == CollectionSort.ratingDesc) {
          onChanged(
            filters.copyWith(ratingAscending: !filters.ratingAscending),
          );
        } else if (s == CollectionSort.bggRatingDesc &&
            filters.sort == CollectionSort.bggRatingDesc) {
          onChanged(
            filters.copyWith(bggRatingAscending: !filters.bggRatingAscending),
          );
        } else if (s == CollectionSort.locationAsc &&
            filters.sort == CollectionSort.locationAsc) {
          onChanged(
            filters.copyWith(locationAscending: !filters.locationAscending),
          );
        } else {
          onChanged(
            filters.copyWith(
              sort: s,
              ratingAscending: false,
              bggRatingAscending: false,
              locationAscending: false,
            ),
          );
        }
      },
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
          child: Text('Ma note'),
        ),
        if (showBoardgameGenreFilter)
          const PopupMenuItem(
            value: CollectionSort.bggRatingDesc,
            child: Text('Note communautaire'),
          ),
        const PopupMenuItem(
          value: CollectionSort.locationAsc,
          child: Text('Localisation'),
        ),
        const PopupMenuItem(
          value: CollectionSort.quantityDesc,
          child: Text('Quantité'),
        ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          visualDensity: VisualDensity.compact,
          foregroundColor: sortActive ? scheme.primary : null,
        ),
        icon: Icon(Icons.sort, size: 18, color: scheme.primary),
        label: const Text('Tri', style: TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _filterMenuButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = filters.hasActiveFilterCriteria;
    return Badge(
      isLabelVisible: active,
      backgroundColor: scheme.primary,
      child: OutlinedButton.icon(
        onPressed: () => _openFilterSheet(context),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          visualDensity: VisualDensity.compact,
          foregroundColor: active ? scheme.primary : null,
        ),
        icon: Icon(Icons.filter_list, size: 18, color: scheme.primary),
        label: const Text('Filtre', style: TextStyle(fontSize: 13)),
      ),
    );
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        var sheetFilters = filters;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void apply(CollectionListFilters next) {
              sheetFilters = next;
              onChanged(next);
              setSheetState(() {});
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.55,
              minChildSize: 0.35,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Text(
                      'Filtres',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (useHolderLocationFilter &&
                        holderFilterOptions.isNotEmpty)
                      _filterSection(
                        context,
                        title: 'Localisation',
                        icon: Icons.place_outlined,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _sheetChip(
                              context,
                              label: 'Tous les lieux',
                              selected: sheetFilters.holderKey == null,
                              onTap: () => apply(
                                sheetFilters.copyWith(clearHolder: true),
                              ),
                            ),
                            for (final opt in holderFilterOptions)
                              _sheetChip(
                                context,
                                label: '${opt.label} (${opt.count})',
                                selected: sheetFilters.holderKey == opt.key,
                                onTap: () => apply(
                                  sheetFilters.copyWith(holderKey: opt.key),
                                ),
                              ),
                          ],
                        ),
                      )
                    else if (showLocationFilter && locations.isNotEmpty)
                      _filterSection(
                        context,
                        title: 'Localisation',
                        icon: Icons.place_outlined,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _sheetChip(
                              context,
                              label: 'Tous les lieux',
                              selected: sheetFilters.locationId == null,
                              onTap: () => apply(
                                sheetFilters.copyWith(clearLocation: true),
                              ),
                            ),
                            for (final loc in locations)
                              _sheetChip(
                                context,
                                label: loc.label,
                                selected: sheetFilters.locationId == loc.id,
                                onTap: () => apply(
                                  sheetFilters.copyWith(locationId: loc.id),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (showFocusFilter)
                      _filterSection(
                        context,
                        title: 'Partage & groupes',
                        icon: Icons.groups_outlined,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _sheetChip(
                              context,
                              label: 'Tout afficher',
                              selected: sheetFilters.ownershipView ==
                                  CollectionOwnershipView.all,
                              onTap: () => apply(
                                sheetFilters.copyWith(
                                  ownershipView: CollectionOwnershipView.all,
                                  clearFocusGroup: true,
                                  clearGroups: true,
                                ),
                              ),
                            ),
                            _sheetChip(
                              context,
                              label: 'Moi uniquement',
                              selected: sheetFilters.ownershipView ==
                                  CollectionOwnershipView.personal,
                              onTap: () => apply(
                                sheetFilters.copyWith(
                                  ownershipView:
                                      CollectionOwnershipView.personal,
                                  clearFocusGroup: true,
                                  clearGroups: true,
                                ),
                              ),
                            ),
                            for (final g in groupOptions)
                              _sheetChip(
                                context,
                                label: g.label,
                                selected: sheetFilters.focusGroupId == g.id,
                                onTap: () => apply(
                                  sheetFilters.copyWith(
                                    ownershipView:
                                        CollectionOwnershipView.groups,
                                    focusGroupId: g.id,
                                    groupIds: {g.id},
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    _filterSection(
                      context,
                      title: 'Type',
                      icon: Icons.category_outlined,
                      child: _buildTypeFilterContent(
                        context,
                        sheetFilters,
                        apply,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: sheetFilters.hasActiveFilterCriteria
                          ? () {
                              apply(
                                CollectionListFilters(
                                  sort: sheetFilters.sort,
                                  ratingAscending: sheetFilters.ratingAscending,
                                  bggRatingAscending:
                                      sheetFilters.bggRatingAscending,
                                  locationAscending:
                                      sheetFilters.locationAscending,
                                ),
                              );
                              Navigator.pop(context);
                            }
                          : null,
                      icon: const Icon(Icons.filter_alt_off),
                      label: const Text('Annuler les filtres'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTypeFilterContent(
    BuildContext context,
    CollectionListFilters activeFilters,
    ValueChanged<CollectionListFilters> apply,
  ) {
    if (showBoardgameGenreFilter && boardgameGenres.isNotEmpty) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _sheetChip(
            context,
            label: 'Tous genres',
            selected: activeFilters.boardgameGenres.isEmpty,
            onTap: () => apply(activeFilters.copyWith(clearBoardgameGenre: true)),
          ),
          for (final genre in boardgameGenres)
            _sheetChip(
              context,
              label: genre,
              selected: activeFilters.boardgameGenres.contains(genre),
              onTap: () {
                final next = Set<String>.from(activeFilters.boardgameGenres);
                if (next.contains(genre)) {
                  next.remove(genre);
                } else {
                  next.add(genre);
                }
                apply(
                  activeFilters.copyWith(
                    boardgameGenres: next,
                    clearBoardgameGenre: next.isEmpty,
                  ),
                );
              },
            ),
        ],
      );
    }
    if (showCardFilter &&
        (cardRarities.isNotEmpty ||
            pokemonTypes.isNotEmpty ||
            cardSubcategoryOptions.isNotEmpty)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => _openCardFilters(context),
            icon: const Icon(Icons.style_outlined, size: 18),
            label: const Text('Ouvrir filtres cartes…'),
          ),
        ],
      );
    }
    if (showTagFilter && tags.isNotEmpty) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _sheetChip(
            context,
            label: 'Tous tags',
            selected: activeFilters.tagId == null,
            onTap: () => apply(activeFilters.copyWith(clearTag: true)),
          ),
          for (final t in tags)
            _sheetChip(
              context,
              label: t.label,
              selected: activeFilters.tagId == t.id,
              onTap: () => apply(activeFilters.copyWith(tagId: t.id)),
              color: t.color,
            ),
        ],
      );
    }
    if (showCardSubcategoryFilter && cardSubcategoryOptions.isNotEmpty) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _sheetChip(
            context,
            label: 'Tous les univers',
            selected: activeFilters.cardSubcategories.isEmpty,
            onTap: () => apply(activeFilters.copyWith(clearCardFilters: true)),
          ),
          for (final sub in cardSubcategoryOptions)
            _sheetChip(
              context,
              label: sub.label,
              selected: activeFilters.cardSubcategories.contains(sub.dbValue),
              onTap: () => apply(
                activeFilters.copyWith(
                  cardSubcategories: {sub.dbValue},
                  cardRarities: {},
                  pokemonTypes: {},
                ),
              ),
              color: sub.color,
            ),
        ],
      );
    }
    return Text(
      'Aucun filtre de type disponible.',
      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
    );
  }

  Widget _filterSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _sheetChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      backgroundColor: color?.withValues(alpha: 0.15),
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

}
