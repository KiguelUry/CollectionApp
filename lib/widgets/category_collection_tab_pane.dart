import 'dart:async';

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
import '../utils/boardgame_language.dart';
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
import 'wishlist/wishlist_budget_banner.dart';
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
  final bool enableBulkSelection;
  final bool defaultWishlistMineFilter;
  final String? currentUserId;
  final Future<void> Function() onReload;
  final Future<void> Function(CollectionItem item) onDeleteItem;
  final Future<void> Function(List<CollectionItem> items)? onBulkDeleteItems;
  final VoidCallback? onBggRatingSortEnrich;
  final bool showExpansionVisibilityToggle;
  final bool showOwnedExpansions;
  final ValueChanged<bool>? onShowOwnedExpansionsChanged;
  final bool showWishlistBudgetBanner;
  final bool showWishlistSortOptions;
  final Set<String> boardgamePreferredLanguages;
  final ValueChanged<Set<String>>? onBoardgamePreferredLanguagesChanged;

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
    this.enableBulkSelection = false,
    this.defaultWishlistMineFilter = false,
    this.currentUserId,
    this.onBulkDeleteItems,
    this.onBggRatingSortEnrich,
    this.showExpansionVisibilityToggle = false,
    this.showOwnedExpansions = false,
    this.onShowOwnedExpansionsChanged,
    this.showWishlistBudgetBanner = false,
    this.showWishlistSortOptions = false,
    this.boardgamePreferredLanguages = const {},
    this.onBoardgamePreferredLanguagesChanged,
  });

  @override
  State<CategoryCollectionTabPane> createState() =>
      _CategoryCollectionTabPaneState();
}

class _CategoryCollectionTabPaneState extends State<CategoryCollectionTabPane>
    with AutomaticKeepAliveClientMixin {
  late CollectionListFilters _filters;
  final _searchController = TextEditingController();
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  final Map<String, GlobalKey> _tileKeys = {};
  String? _highlightItemId;
  Timer? _highlightTimer;
  Offset? _marqueePointerDown;
  Offset? _marqueeCurrent;
  bool _marqueeDragging = false;
  Set<String> _marqueeBaseSelection = {};

  @override
  void initState() {
    super.initState();
    _filters = widget.defaultWishlistMineFilter &&
            widget.currentUserId != null
        ? CollectionListFilters(
            wishlistMineOnly: true,
            wishlistMineUserId: widget.currentUserId,
          )
        : CollectionListFilters();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _focusExpansionBase(CollectionItem base) async {
    _tileKeys.putIfAbsent(base.id, GlobalKey.new);
    setState(() => _highlightItemId = base.id);
    _highlightTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tileKeys[base.id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeInOutCubic,
          alignment: 0.2,
        );
      }
    });
    _highlightTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _highlightItemId = null);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Extension de « ${base.title} »'),
        duration: const Duration(seconds: 2),
      ),
    );
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
      _tileKeys.clear();
      _marqueePointerDown = null;
      _marqueeCurrent = null;
      _marqueeDragging = false;
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

  void _selectAll(List<CollectionItem> filtered) {
    for (final item in filtered) {
      _selectedIds.add(item.id);
    }
  }

  Rect? get _marqueeRect {
    if (_marqueePointerDown == null || _marqueeCurrent == null) return null;
    return Rect.fromPoints(_marqueePointerDown!, _marqueeCurrent!);
  }

  Set<String> _itemIdsInMarquee(Rect rect) {
    final ids = <String>{};
    for (final entry in _tileKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final tileRect = topLeft & box.size;
      if (rect.overlaps(tileRect)) ids.add(entry.key);
    }
    return ids;
  }

  void _onSelectionPointerDown(PointerDownEvent event) {
    if (!_selectionMode) return;
    _marqueePointerDown = event.position;
    _marqueeCurrent = event.position;
    _marqueeDragging = false;
    _marqueeBaseSelection = Set<String>.from(_selectedIds);
  }

  void _onSelectionPointerMove(PointerMoveEvent event) {
    if (!_selectionMode || _marqueePointerDown == null) return;
    if (!_marqueeDragging &&
        (event.position - _marqueePointerDown!).distance > 10) {
      _marqueeDragging = true;
    }
    if (!_marqueeDragging) return;
    final rect = Rect.fromPoints(_marqueePointerDown!, event.position);
    final inRect = _itemIdsInMarquee(rect);
    setState(() {
      _marqueeCurrent = event.position;
      _selectedIds
        ..clear()
        ..addAll(_marqueeBaseSelection)
        ..addAll(inRect);
    });
  }

  void _onSelectionPointerUp(PointerEvent event) {
    _onSelectionPointerEnd();
  }

  void _onSelectionPointerEnd() {
    if (!_selectionMode) return;
    setState(() {
      _marqueePointerDown = null;
      _marqueeCurrent = null;
      _marqueeDragging = false;
    });
  }

  List<CollectionItem> _selectedItems(List<CollectionItem> filtered) =>
      filtered.where((i) => _selectedIds.contains(i.id)).toList();

  Future<void> _manageSelectedGroups(List<CollectionItem> filtered) async {
    final selected = _selectedItems(filtered);
    if (selected.isEmpty) return;
    final ok = await showBulkGroupManageSheet(
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

  Future<void> _bulkDeleteSelected(List<CollectionItem> filtered) async {
    final selected = _selectedItems(filtered);
    if (selected.isEmpty) return;
    final count = selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer $count objet${count > 1 ? 's' : ''} ?'),
        content: Text(
          count == 1
              ? '« ${selected.first.title} » sera retiré de ta liste.'
              : '$count objets seront retirés de ta liste.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    if (widget.onBulkDeleteItems != null) {
      await widget.onBulkDeleteItems!(selected);
    } else {
      for (final item in selected) {
        await widget.onDeleteItem(item);
      }
    }
    if (mounted) {
      _exitSelectionMode();
      await widget.onReload();
    }
  }

  Widget? _buildBulkSelectionBar(List<CollectionItem> filtered) {
    if (!widget.enableBulkSelection) return null;
    final hasGroups = widget.boardgameGroups.isNotEmpty;
    final allSelected = filtered.isNotEmpty &&
        filtered.every((i) => _selectedIds.contains(i.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          if (_selectionMode) ...[
            TextButton(onPressed: _exitSelectionMode, child: const Text('Annuler')),
            if (filtered.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  if (allSelected) {
                    _selectedIds.clear();
                  } else {
                    _selectAll(filtered);
                  }
                }),
                child: Text(allSelected ? 'Tout désél.' : 'Tout sélect.'),
              ),
            Expanded(
              child: Text(
                '${_selectedIds.length} sélectionné${_selectedIds.length > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasGroups)
              IconButton(
                tooltip: 'Groupes',
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => _manageSelectedGroups(filtered),
                icon: const Icon(Icons.groups_outlined, size: 22),
              ),
            IconButton(
              tooltip: 'Supprimer',
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => _bulkDeleteSelected(filtered),
              icon: Icon(Icons.delete_outline, size: 22, color: Colors.red.shade700),
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
          left: 4,
          child: Material(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black54,
            shape: const CircleBorder(),
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
      ],
    );
  }

  Widget _buildTile({
    required CollectionItem item,
    required int totalQuantity,
    required bool showDuplicateBadge,
    required Map<String, int> ownedIndex,
    required Map<String, int> groupActivity,
    required bool isGrid,
  }) {
    final trackKeys = widget.category == CollectionCategory.boardgame &&
        !_selectionMode;
    if (_selectionMode || trackKeys) {
      _tileKeys.putIfAbsent(item.id, GlobalKey.new);
    }

    final expansionFocus = trackKeys ? _focusExpansionBase : null;

    final tile = isGrid
        ? CollectionItemTile(
            key: ValueKey(item.id),
            item: item,
            category: widget.category,
            totalQuantity: totalQuantity,
            ownedQuantity: ownedQuantityFor(item, ownedIndex),
            showDuplicateBadge: showDuplicateBadge,
            compactCover: true,
            groupNamesById: widget.groupNamesById,
            boardgameQuickEditGroups:
                widget.category == CollectionCategory.boardgame &&
                        !_selectionMode
                    ? widget.boardgameGroups
                    : null,
            groupActivityCounts: groupActivity,
            onExpansionBaseFocus: expansionFocus,
            onDelete: _selectionMode ? null : () => widget.onDeleteItem(item),
            onTap: _selectionMode
                ? () => _toggleSelection(item.id)
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ItemDetailScreen(
                          item: item.copyWith(quantity: totalQuantity),
                          ownedQuantity: ownedQuantityFor(item, ownedIndex),
                        ),
                      ),
                    ),
            onLongPress: _selectionMode
                ? null
                : item.imageUrl != null && item.imageUrl!.trim().isNotEmpty
                    ? () => showCoverPreview(
                          context,
                          imageUrl: item.imageUrl,
                          title: item.title,
                          bookCover:
                              widget.category == CollectionCategory.book,
                        )
                    : null,
          )
        : CollectionItemListTile(
            key: ValueKey(item.id),
            item: item,
            category: widget.category,
            totalQuantity: totalQuantity,
            ownedQuantity: ownedQuantityFor(item, ownedIndex),
            boardgameQuickEditGroups:
                widget.category == CollectionCategory.boardgame &&
                        !_selectionMode
                    ? widget.boardgameGroups
                    : null,
            groupActivityCounts: groupActivity,
            onExpansionBaseFocus: expansionFocus,
            onDelete: _selectionMode ? null : () => widget.onDeleteItem(item),
            onTap: _selectionMode
                ? () => _toggleSelection(item.id)
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ItemDetailScreen(
                          item: item.copyWith(quantity: totalQuantity),
                          ownedQuantity: ownedQuantityFor(item, ownedIndex),
                        ),
                      ),
                    ),
          );

    Widget keyed = (_selectionMode || trackKeys)
        ? KeyedSubtree(key: _tileKeys[item.id], child: tile)
        : tile;

    if (_highlightItemId == item.id) {
      keyed = AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.deepPurple.shade400,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.withValues(alpha: 0.35),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: keyed,
      );
    }

    return _wrapSelectable(keyed, item.id);
  }

  Widget _withMarqueeOverlay(Widget child) {
    if (!_selectionMode) return child;
    return Stack(
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onSelectionPointerDown,
          onPointerMove: _onSelectionPointerMove,
          onPointerUp: _onSelectionPointerUp,
          onPointerCancel: _onSelectionPointerUp,
          child: child,
        ),
        if (_marqueeRect case final rect?)
          Positioned.fill(
            child: Builder(
              builder: (context) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return const SizedBox.shrink();
                final localRect = Rect.fromPoints(
                  box.globalToLocal(rect.topLeft),
                  box.globalToLocal(rect.bottomRight),
                );
                return IgnorePointer(
                  child: CustomPaint(
                    size: box.size,
                    painter: _MarqueePainter(rect: localRect),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = widget.items;
    var filtered = _filters.apply(items);
    if (widget.category == CollectionCategory.boardgame &&
        widget.boardgamePreferredLanguages.isNotEmpty) {
      filtered = filtered
          .where(
            (i) => itemMatchesBoardgameLanguages(
              i.metadata,
              widget.boardgamePreferredLanguages,
            ),
          )
          .toList();
    }
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
          showWishlistMineToggle: widget.defaultWishlistMineFilter,
          showExpansionVisibilityToggle: widget.showExpansionVisibilityToggle,
          showOwnedExpansions: widget.showOwnedExpansions,
          onShowOwnedExpansionsChanged: widget.onShowOwnedExpansionsChanged,
          showWishlistSortOptions: widget.showWishlistSortOptions,
          boardgamePreferredLanguages: widget.boardgamePreferredLanguages,
          onBoardgamePreferredLanguagesChanged:
              widget.onBoardgamePreferredLanguagesChanged,
        ),
        ?_buildBulkSelectionBar(filtered),
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
          child: widget.showWishlistBudgetBanner
              ? Column(
                  children: [
                    Expanded(
                      child: widget.category == CollectionCategory.media &&
                              widget.mediaGroupByArtist
                          ? _buildMediaArtistList(filtered)
                          : widget.viewMode == CollectionViewMode.grid
                              ? _buildGrid(filtered)
                              : _buildList(filtered),
                    ),
                    WishlistBudgetBanner(items: filtered),
                  ],
                )
              : widget.category == CollectionCategory.media &&
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
                  _filters = widget.defaultWishlistMineFilter &&
                          widget.currentUserId != null
                      ? CollectionListFilters(
                          wishlistMineOnly: true,
                          wishlistMineUserId: widget.currentUserId,
                        )
                      : CollectionListFilters();
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
        child: _withMarqueeOverlay(
          GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            cacheExtent: 480,
            addRepaintBoundaries: false,
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
                child: _buildTile(
                  item: item,
                  totalQuantity: entry.totalQuantity,
                  showDuplicateBadge: entry.hasDuplicates,
                  ownedIndex: ownedIndex,
                  groupActivity: groupActivity,
                  isGrid: true,
                ),
              );
            },
          ),
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
      child: _withMarqueeOverlay(
        ListView.builder(
          cacheExtent: 480,
          addRepaintBoundaries: false,
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: grouped.length,
          itemBuilder: (context, index) {
            final entry = grouped[index];
            final item = entry.item;
            return RepaintBoundary(
              child: _buildTile(
                item: item,
                totalQuantity: entry.totalQuantity,
                showDuplicateBadge: entry.hasDuplicates,
                ownedIndex: ownedIndex,
                groupActivity: groupActivity,
                isGrid: false,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MarqueePainter extends CustomPainter {
  final Rect rect;

  _MarqueePainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = const Color(0x332196F3)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(covariant _MarqueePainter oldDelegate) =>
      oldDelegate.rect != rect;
}
