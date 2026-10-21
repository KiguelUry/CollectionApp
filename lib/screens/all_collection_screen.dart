import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../models/collection_view_mode.dart';
import '../models/item_tag.dart';
import '../models/storage_location.dart';
import '../models/user_collection_type.dart';
import '../services/collection_change_history_service.dart';
import '../services/collection_local_cache.dart';
import '../services/collection_refresh.dart';
import '../services/global_play_history_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/supabase_capacity.dart';
import '../services/tag_service.dart';
import '../utils/active_categories.dart';
import '../utils/boardgame_collection_visibility.dart';
import '../utils/category_hub_order.dart';
import '../utils/collection_grid_layout.dart';
import '../utils/collection_item_filters.dart';
import '../utils/debounced_runner.dart';
import '../utils/holder_filter.dart';
import '../utils/hub_category_visibility.dart';
import '../utils/owned_quantity_index.dart';
import '../utils/supabase_embeds.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/category_collection_tab_pane.dart';
import '../widgets/collection_item_tile.dart';
import 'item_detail_screen.dart';

/// Filtre de l'écran : une catégorie standard ou une collection perso.
class _Facet {
  final CollectionCategory category;
  final UserCollectionType? customType;

  const _Facet(this.category, [this.customType]);

  String get key => customType != null
      ? 'custom:${customType!.id}'
      : 'cat:${category.dbValue}';
  String get label => customType?.name ?? category.label;
  IconData get icon => category.icon;
  Color get color => customType?.color ?? category.color;

  bool matches(CollectionItem item) => customType != null
      ? item.category == CollectionCategory.custom &&
          item.subcategory == customType!.id
      : item.category == category;
}

/// Tous les objets possédés, toutes catégories confondues.
class AllCollectionScreen extends StatefulWidget {
  const AllCollectionScreen({super.key});

  @override
  State<AllCollectionScreen> createState() => _AllCollectionScreenState();
}

class _AllCollectionScreenState extends State<AllCollectionScreen> {
  static const _cacheScope = 'all_owned';

  final _tagService = TagService();
  final _searchController = TextEditingController();
  final _reloadDebounce = DebouncedRunner();
  late final String _userId;

  List<Map<String, dynamic>> _rows = [];
  List<CollectionItem>? _enriched;
  bool _loading = true;
  List<HubTileEntry> _hubTiles = [];
  Set<CollectionCategory> _active = CollectionCategory.defaultActive;
  List<CollectionGroup> _groups = [];
  Set<String> _myGroupIds = {};
  Map<String, String> _groupNamesById = {};
  List<StorageLocation> _locations = [];
  List<ItemTag> _tags = [];
  String? _selectedKey;
  String _query = '';
  CollectionViewMode _viewMode = CollectionViewMode.grid;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser!.id;
    final cached = CollectionLocalCache.peek(_userId, _cacheScope);
    if (cached != null) {
      _rows = cached;
      _loading = false;
      _enrich();
    } else {
      unawaited(_restoreFromDisk());
    }
    CollectionRefresh.instance.addListener(_scheduleReload);
    _loadSideData();
    _reload();
  }

  @override
  void dispose() {
    CollectionRefresh.instance.removeListener(_scheduleReload);
    _reloadDebounce.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleReload() => _reloadDebounce.run(
        delay: const Duration(milliseconds: 300),
        action: () {
          if (mounted) unawaited(_reload());
        },
      );

  bool _synced = false;

  Future<void> _restoreFromDisk() async {
    final rows = await CollectionLocalCache.read(_userId, _cacheScope);
    if (rows == null || !mounted || _synced) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
    _enrich();
  }

  Future<void> _reload() async {
    try {
      final client = Supabase.instance.client;
      // Groupes + objets perso + objets de groupe en parallèle (0 s d'attente).
      final groupsFuture = _groups.isEmpty
          ? GroupService().fetchMyGroups()
          : Future.value(_groups);
      final personalFuture = client
          .from('collection_items')
          .select(SupabaseEmbeds.collectionItemList)
          .eq('is_wishlist', false)
          .eq('added_by', _userId);

      final groups = await groupsFuture;
      final groupIds = groups.map((g) => g.id).toList();
      final groupFuture = groupIds.isEmpty
          ? Future.value(<dynamic>[])
          : client
              .from('collection_items')
              .select(SupabaseEmbeds.collectionItemList)
              .eq('is_wishlist', false)
              .inFilter('group_id', groupIds);

      final personalRows = await personalFuture;
      final groupRows = await groupFuture;
      if (!mounted) return;

      final byId = <String, Map<String, dynamic>>{};
      for (final raw in [...personalRows, ...groupRows]) {
        final map = Map<String, dynamic>.from(raw as Map);
        final id = map['id']?.toString();
        if (id != null && id.isNotEmpty) byId[id] = map;
      }
      final rows = byId.values.toList();
      _synced = true;
      CollectionLocalCache.write(_userId, _cacheScope, rows);
      setState(() {
        _rows = rows;
        _loading = false;
        if (groups.isNotEmpty) {
          _groups = groups;
          _myGroupIds = groups.map((g) => g.id).toSet();
          _groupNamesById = {for (final g in groups) g.id: g.name};
        }
      });
      _enrich();
    } catch (e) {
      final degraded = SupabaseCapacity.markDegraded(e);
      if (!mounted) return;
      if (degraded) {
        final local = await CollectionLocalCache.read(_userId, _cacheScope);
        if (local != null && local.isNotEmpty && mounted) {
          setState(() {
            _rows = local;
            _loading = false;
          });
          _enrich();
        } else if (mounted) {
          setState(() => _loading = false);
        }
        if (mounted) SupabaseCapacity.showOfflineSnackIfNeeded(context);
      } else if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadSideData() async {
    try {
      final results = await Future.wait([
        loadVisibleHubTiles(),
        GroupService().fetchMyGroups(),
        LocationService().fetchLocations(),
        _tagService.fetchMyTags(),
      ]);
      if (!mounted) return;
      final groups = results[1] as List<CollectionGroup>;
      final active = await ActiveCategories.load();
      if (!mounted) return;
      setState(() {
        _active = active;
        _hubTiles = results[0] as List<HubTileEntry>;
        _groups = groups;
        _myGroupIds = groups.map((g) => g.id).toSet();
        _groupNamesById = {for (final g in groups) g.id: g.name};
        _locations = results[2] as List<StorageLocation>;
        _tags = results[3] as List<ItemTag>;
      });
    } catch (_) {}
  }

  int _enrichGen = 0;

  void _enrich() {
    final gen = ++_enrichGen;
    _tagService.enrichItems(_parse(_rows)).then((items) {
      if (!mounted || gen != _enrichGen) return;
      setState(() => _enriched = items);
    });
  }

  List<CollectionItem> _parse(List<Map<String, dynamic>> rows) => [
        for (final r in rows) CollectionItem.fromJson(r),
      ];

  bool _categoryAllowed(CollectionItem item) {
    if (item.category == CollectionCategory.custom) {
      return _hubTiles.any((e) => e.customType?.id == item.subcategory);
    }
    return _active.contains(item.category);
  }

  /// Mes objets + ceux de mes groupes, catégories actives, hors extensions.
  List<CollectionItem> get _items {
    final all = (_enriched ?? _parse(_rows)).where((i) {
      if (!isActiveCollectionItem(i) || i.isSold) return false;
      if (!_categoryAllowed(i)) return false;
      if (i.addedBy == _userId || i.locationUserId == _userId) return true;
      final gid = i.groupId;
      return gid != null && _myGroupIds.contains(gid);
    }).toList();
    final boardgames =
        all.where((i) => i.category == CollectionCategory.boardgame).toList();
    return all
        .where(
          (i) =>
              i.category != CollectionCategory.boardgame ||
              !isBoardgameHiddenInGlobalCollection(i, boardgames),
        )
        .toList();
  }

  /// Facettes dans l'ordre du hub, seulement celles qui ont des objets.
  List<_Facet> _facets(List<CollectionItem> items) {
    final facets = <_Facet>[];
    final seen = <String>{};
    for (final e in _hubTiles) {
      final f = e.customType != null
          ? _Facet(CollectionCategory.custom, e.customType)
          : _Facet(e.category!);
      if (seen.add(f.key) && items.any(f.matches)) facets.add(f);
    }
    for (final c in CollectionCategory.values) {
      if (c == CollectionCategory.custom) continue;
      final f = _Facet(c);
      if (seen.add(f.key) && items.any(f.matches)) facets.add(f);
    }
    return facets;
  }

  void _openItem(CollectionItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
    );
  }

  Future<void> _deleteItem(CollectionItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('« ${item.title} » sera retiré de ta collection.'),
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
    if (ok != true || !mounted) return;
    await _deleteSilently(item);
    CollectionRefresh.instance.bump();
  }

  Future<void> _deleteSilently(CollectionItem item) async {
    await CollectionChangeHistoryService.instance.recordDeleted(item);
    if (item.category == CollectionCategory.boardgame) {
      await GlobalPlayHistoryService().archivePlaysFromDeletedItem(item);
    }
    await Supabase.instance.client
        .from('collection_items')
        .delete()
        .eq('id', item.id);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final facets = _facets(items);
    final selected = facets.where((f) => f.key == _selectedKey).firstOrNull;

    return Scaffold(
      appBar: AppAppBar(
        title: 'Toute ma collection',
        actions: [
          if (selected != null)
            IconButton(
              tooltip: _viewMode == CollectionViewMode.grid
                  ? 'Vue liste'
                  : 'Vue grille',
              icon: Icon(
                _viewMode == CollectionViewMode.grid
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
              ),
              onPressed: () => setState(
                () => _viewMode = _viewMode == CollectionViewMode.grid
                    ? CollectionViewMode.list
                    : CollectionViewMode.grid,
              ),
            ),
        ],
      ),
      body: CollectionGridLayout.constrainOnWebDesktop(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFacetChips(items, facets, selected),
            Expanded(
              child: _loading && items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : selected == null
                      ? _buildOverview(items)
                      : _buildFacetPane(items, selected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacetChips(
    List<CollectionItem> items,
    List<_Facet> facets,
    _Facet? selected,
  ) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              showCheckmark: false,
              avatar: const Icon(Icons.all_inbox_rounded, size: 18),
              label: Text('Tout · ${items.length}'),
              selected: selected == null,
              onSelected: (_) => setState(() => _selectedKey = null),
            ),
          ),
          for (final f in facets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                avatar: Icon(
                  f.icon,
                  size: 18,
                  color: selected?.key == f.key ? null : f.color,
                ),
                label: Text('${f.label} · ${items.where(f.matches).length}'),
                selected: selected?.key == f.key,
                selectedColor: f.color.withValues(alpha: 0.22),
                onSelected: (_) => setState(() => _selectedKey = f.key),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Vue Tout

  Widget _buildOverview(List<CollectionItem> items) {
    final q = _query.trim().toLowerCase();
    final visible = (q.isEmpty
            ? items
            : items.where((i) => i.title.toLowerCase().contains(q)))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final ownedIndex = buildOwnedQuantityIndex(items);

    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Chercher dans toute ma collection',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  suffixIcon: q.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          if (visible.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('Ta collection est vide pour l\'instant.'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
              sliver: SliverGrid(
                gridDelegate: CollectionGridLayout.collectionDelegate(
                  context,
                  CollectionCategory.boardgame,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final item = visible[i];
                    return CollectionItemTile(
                      item: item,
                      category: item.category,
                      totalQuantity: item.quantity,
                      ownedQuantity: ownedQuantityFor(item, ownedIndex),
                      showDuplicateBadge: item.quantity > 1,
                      groupNamesById: _groupNamesById,
                      boardgameQuickEditGroups:
                          item.category == CollectionCategory.boardgame
                              ? _groups
                              : null,
                      compactCover: true,
                      onTap: () => _openItem(item),
                    );
                  },
                  childCount: visible.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------- Vue par catégorie

  Widget _buildFacetPane(List<CollectionItem> items, _Facet facet) {
    final list = items.where(facet.matches).toList();
    final isBoardgame = facet.category == CollectionCategory.boardgame;
    return CategoryCollectionTabPane(
      key: ValueKey('all_${facet.key}'),
      category: facet.category,
      items: list,
      ownedQuantityIndex: buildOwnedQuantityIndex(list),
      groupActivityCounts: const {},
      holderFilterOptions:
          isBoardgame ? buildHolderFilterOptions(list) : const [],
      groupNamesById: _groupNamesById,
      boardgameGroups: _groups,
      locations: _locations,
      tags: _tags,
      viewMode: _viewMode,
      mediaGroupByArtist: false,
      onMediaGroupByArtistChanged: (_) {},
      emptyHint: 'Rien ici pour l\'instant.',
      showLocationFilter: !isBoardgame,
      showTagFilter: !isBoardgame,
      enableBulkSelection: true,
      currentUserId: _userId,
      onReload: _reload,
      onDeleteItem: _deleteItem,
      onBulkDeleteItems: (items) async {
        for (final item in items) {
          await _deleteSilently(item);
        }
        CollectionRefresh.instance.bump();
      },
    );
  }
}
