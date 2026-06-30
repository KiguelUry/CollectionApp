import 'package:flutter/material.dart';

import '../models/card_subcategory.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../models/collection_list_filters.dart';
import '../models/collection_view_mode.dart';
import '../models/item_tag.dart';
import '../models/storage_location.dart';
import '../screens/item_detail_screen.dart';
import '../screens/media_artist_albums_screen.dart';
import '../utils/boardgame_genres.dart';
import '../utils/card_item_metadata.dart';
import '../utils/collection_count_label.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_grid_layout.dart';
import '../utils/holder_filter.dart';
import '../utils/owned_quantity_index.dart';
import '../utils/tcg_rarity_order.dart';
import 'collection_filter_bar.dart';
import 'collection_item_list_tile.dart';
import 'collection_item_tile.dart';
import 'cover_preview_sheet.dart';
import 'wishlist_suggestions_banner.dart';
import 'bulk_group_assign_sheet.dart';

/// Onglet Collection ou Wishlist isolé (filtres locaux → moins de rebuilds).
class CategoryCollectionTabPane extends StatefulWidget {
  final CollectionCategory category;
  final CardSubcategory? fixedCardSubcategory;
  final List<CollectionItem> items;
  final Map<String, int> ownedQuantityIndex;
  final Map<String, int> groupActivityCounts;
  final List<HolderFilterOption> holderFilterOptions;
  final Map<String, String> groupNamesById;
  final List<CollectionGroup> boardgameGroups;
  final List<StorageLocation> locations;
  final List<ItemTag> tags;
  final CollectionViewMode viewMode;
  final bool mediaGroupByArtist;
  final ValueChanged<bool> onMediaGroupByArtistChanged;
  final String emptyHint;
  final bool showFocusFilter;
  final bool showLocationFilter;
  final bool showTagFilter;
  final bool showWishlistSuggestions;
  final bool enableBulkGroupAssign;
  final Future<void> Function() onReload;
  final Future<void> Function(CollectionItem item) onDeleteItem;
  final VoidCallback? onBggRatingSortEnrich;

  const CategoryCollectionTabPane({
    super.key,
    required this.category,
    this.fixedCardSubcategory,
    required this.items,
    required this.ownedQuantityIndex,
    required this.groupActivityCounts,
    required this.holderFilterOptions,
    required this.groupNamesById,
    required this.boardgameGroups,
    required this.locations,
    required this.tags,
    required this.viewMode,
    required this.mediaGroupByArtist,
    required this.onMediaGroupByArtistChanged,
    required this.emptyHint,
    required this.onReload,
    required this.onDeleteItem,
    this.showFocusFilter = true,
    this.showLocationFilter = true,
    this.showTagFilter = true,
    this.showWishlistSuggestions = false,
    this.enableBulkGroupAssign = false,
    this.onBggRatingSortEnrich,
  });

  @override
  State<CategoryCollectionTabPane> createState() =>
      _CategoryCollectionTabPaneState();
}

class _CategoryCollectionTabPaneState extends State<CategoryCollectionTabPane>
    with AutomaticKeepAliveClientMixin {
  CollectionListFilters _filters = CollectionListFilters();
  final _searchController = TextEditingController();
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _countLabel(List<CollectionItem> items, List<CollectionItem> filtered) {
    if (filtered.length != items.length) {
      return '${filtered.length} sur ${items.length}';
    }
    final inGroup = items.where((i) => i.isGroupOwned).length;
    return formatCollectionCountLabel(total: items.length, inGroup: inGroup);
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String itemId) {
    setState(() {
      if (_selectedIds.contains(itemId)) {
        _selectedIds.remove(itemId);
      } else {
        _selectedIds.add(itemId);
      }
    });
  }

  Future<void> _assignSelectedToGroup(List<CollectionItem> filtered) async {
    final selected = filtered.where((i) => _selectedIds.contains(i.id)).toList();
    if (selected.isEmpty) return;
    final ok = await showBulkGroupAssignSheet(
      context,
      items: selected,
      groups: widget.boardgameGroups,
      groupActivityCounts: widget.groupActivityCounts,
    );
    if (ok && mounted) {
      _exitSelectionMode();
      await widget.onReload();
    }
  }

  Widget? _buildBulkSelectionBar(List<CollectionItem> filtered) {
    if (!widget.enableBulkGroupAssign || widget.boardgameGroups.isEmpty) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          if (_selectionMode) ...[
            TextButton(onPressed: _exitSelectionMode, child: const Text('Annuler')),
            Expanded(
              child: Text(
                '${_selectedIds.length} sélectionné${_selectedIds.length > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => _assignSelectedToGroup(filtered),
              icon: const Icon(Icons.groups_outlined, size: 18),
              label: const Text('Groupe'),
            ),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _selectionMode = true),
                icon: const Icon(Icons.checklist_rounded, size: 18),
                label: const Text('Sélection multiple'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wrapSelectable(Widget child, String itemId) {
    if (!_selectionMode) return child;
    final selected = _selectedIds.contains(itemId);
    return Stack(
      children: [
        child,
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _toggleSelection(itemId),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  selected ? Icons.check_rounded : Icons.circle_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = widget.items;
    final filtered = _filters.apply(items);
    final countLabel = _countLabel(items, filtered);
    final groupOptions = widget.groupNamesById.entries
        .map((e) => GroupFilterOption(id: e.key, label: e.value))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    final cardSubcategoryOptions = widget.category == CollectionCategory.card &&
            widget.fixedCardSubcategory == null
        ? distinctCardSubcategories(items)
        : const <CardSubcategory>[];
    final selectedUniverse = widget.fixedCardSubcategory?.dbValue ??
        (_filters.cardSubcategories.length == 1
            ? _filters.cardSubcategories.first
            : null);
    final universeSub = selectedUniverse != null
        ? CardSubcategory.fromDbValue(selectedUniverse)
        : null;
    final universeScoped = selectedUniverse != null
        ? items.where((i) => i.subcategory == selectedUniverse).toList()
        : items;
    final cardRarityOptions = widget.category == CollectionCategory.card &&
            universeSub != null
        ? sortRarityLabels(
            distinctCardRarities(universeScoped).toList(),
            universeSub,
          )
        : const <String>[];
    final pokemonTypeOptions = widget.category == CollectionCategory.card &&
            universeSub == CardSubcategory.pokemon
        ? (distinctPokemonTypes(universeScoped).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showWishlistSuggestions)
          WishlistSuggestionsBanner(category: widget.category),
        if (widget.category == CollectionCategory.media)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Par artiste'),
                selected: widget.mediaGroupByArtist,
                onSelected: widget.onMediaGroupByArtistChanged,
                avatar: const Icon(Icons.person_outline, size: 18),
              ),
            ),
          ),
        CollectionFilterBar(
          filters: _filters,
          onChanged: (f) {
            setState(() => _filters = f);
            if (widget.category == CollectionCategory.boardgame &&
                f.sort == CollectionSort.bggRatingDesc) {
              widget.onBggRatingSortEnrich?.call();
            }
          },
          searchController: _searchController,
          locations: widget.locations,
          tags: widget.tags,
          showFocusFilter: widget.showFocusFilter,
          showLocationFilter: widget.showLocationFilter,
          showTagFilter: widget.showTagFilter,
          showBoardgameGenreFilter:
              widget.category == CollectionCategory.boardgame,
          boardgameGenres: widget.category == CollectionCategory.boardgame
              ? distinctBoardgameGenres(items)
              : const [],
          showCardFilter: false,
          showCardSubcategoryFilter: cardSubcategoryOptions.isNotEmpty,
          showCardUniverseDetailFilters: universeSub != null,
          cardRarities: cardRarityOptions,
          pokemonTypes: pokemonTypeOptions,
          cardSubcategoryOptions: cardSubcategoryOptions,
          groupOptions: groupOptions,
          holderFilterOptions: widget.category == CollectionCategory.boardgame
              ? widget.holderFilterOptions
              : const [],
          useHolderLocationFilter:
              widget.category == CollectionCategory.boardgame,
        ),
        if (_buildBulkSelectionBar(filtered) != null)
          _buildBulkSelectionBar(filtered)!,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Text(
            countLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: widget.category == CollectionCategory.media &&
                  widget.mediaGroupByArtist
              ? _buildMediaArtistList(filtered)
              : widget.viewMode == CollectionViewMode.grid
                  ? _buildGrid(filtered)
                  : _buildList(filtered),
        ),
      ],
    );
  }

  Widget _buildMediaArtistList(List<CollectionItem> items) {
    if (items.isEmpty) return _emptyState();
    final byArtist = <String, List<CollectionItem>>{};
    for (final item in items) {
      final raw = item.metadata?['artist']?.toString().trim();
      final key = raw != null && raw.isNotEmpty ? raw : 'Artiste inconnu';
      byArtist.putIfAbsent(key, () => []).add(item);
    }
    final artists = byArtist.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: artists.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final name = artists[index];
        final albums = byArtist[name]!;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: widget.category.color.withValues(alpha: 0.2),
            child: Icon(Icons.person, color: widget.category.color),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${albums.length} album${albums.length > 1 ? 's' : ''}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => MediaArtistAlbumsScreen(
                artist: name,
                items: albums,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              widget.emptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (_filters.hasActiveFilterCriteria) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _filters = CollectionListFilters();
                  _searchController.clear();
                }),
                child: const Text('Réinitialiser les filtres'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<CollectionItem> items) {
    if (items.isEmpty) return _emptyState();
    final grouped = CollectionGridGrouper.group(items);
    final ownedIndex = widget.ownedQuantityIndex;
    final groupActivity = widget.groupActivityCounts;

    return CollectionGridLayout.constrainOnWebDesktop(
      context: context,
      child: RefreshIndicator(
        onRefresh: widget.onReload,
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          cacheExtent: 480,
          addRepaintBoundaries: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: CollectionGridLayout.crossAxisCount(context),
            crossAxisSpacing: CollectionGridLayout.gridCrossSpacing,
            mainAxisSpacing: CollectionGridLayout.gridMainSpacing,
            childAspectRatio:
                CollectionGridLayout.aspectRatio(widget.category, context),
          ),
          itemCount: grouped.length,
          itemBuilder: (context, index) {
            final entry = grouped[index];
            final item = entry.item;
            return RepaintBoundary(
              child: _wrapSelectable(
                CollectionItemTile(
                  key: ValueKey(item.id),
                  item: item,
                  category: widget.category,
                  totalQuantity: entry.totalQuantity,
                  ownedQuantity: ownedQuantityFor(item, ownedIndex),
                  showDuplicateBadge: entry.hasDuplicates,
                  groupNamesById: widget.groupNamesById,
                  boardgameQuickEditGroups:
                      widget.category == CollectionCategory.boardgame
                          ? widget.boardgameGroups
                          : null,
                  groupActivityCounts: groupActivity,
                  onDelete: () => widget.onDeleteItem(item),
                  onTap: _selectionMode
                      ? () => _toggleSelection(item.id)
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ItemDetailScreen(
                                item: item.copyWith(
                                  quantity: entry.totalQuantity,
                                ),
                                ownedQuantity:
                                    ownedQuantityFor(item, ownedIndex),
                              ),
                            ),
                          ),
                  onLongPress: _selectionMode
                      ? null
                      : item.imageUrl != null &&
                              item.imageUrl!.trim().isNotEmpty
                          ? () => showCoverPreview(
                                context,
                                imageUrl: item.imageUrl,
                                title: item.title,
                                bookCover:
                                    widget.category == CollectionCategory.book,
                              )
                          : null,
                ),
                item.id,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(List<CollectionItem> items) {
    if (items.isEmpty) return _emptyState();
    final grouped = CollectionGridGrouper.group(items);
    final ownedIndex = widget.ownedQuantityIndex;
    final groupActivity = widget.groupActivityCounts;

    return RefreshIndicator(
      onRefresh: widget.onReload,
      child: ListView.builder(
        cacheExtent: 480,
        addRepaintBoundaries: true,
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final entry = grouped[index];
          final item = entry.item;
          return RepaintBoundary(
            child: _wrapSelectable(
              CollectionItemListTile(
                key: ValueKey(item.id),
                item: item,
                category: widget.category,
                totalQuantity: entry.totalQuantity,
                ownedQuantity: ownedQuantityFor(item, ownedIndex),
                boardgameQuickEditGroups:
                    widget.category == CollectionCategory.boardgame
                        ? widget.boardgameGroups
                        : null,
                groupActivityCounts: groupActivity,
                onDelete: () => widget.onDeleteItem(item),
                onTap: _selectionMode
                    ? () => _toggleSelection(item.id)
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ItemDetailScreen(
                              item: item.copyWith(
                                quantity: entry.totalQuantity,
                              ),
                              ownedQuantity:
                                  ownedQuantityFor(item, ownedIndex),
                            ),
                          ),
                        ),
              ),
              item.id,
            ),
          );
        },
      ),
    );
  }
}
