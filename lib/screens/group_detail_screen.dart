import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_grid_layout.dart';
import '../utils/collection_item_filters.dart';
import '../services/group_service.dart';
import '../models/collection_list_filters.dart';
import '../models/collection_view_mode.dart';
import '../models/item_tag.dart';
import '../models/storage_location.dart';
import '../services/location_service.dart';
import '../services/tag_service.dart';
import '../widgets/collection_filter_bar.dart';
import '../widgets/collection_item_list_tile.dart';
import '../widgets/collection_item_tile.dart';
import '../navigation/app_navigation.dart';
import '../widgets/group_badge.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/group_members_sheet.dart';
import '../widgets/group_stats_banner.dart';
import 'group_edit_screen.dart';
import 'item_detail_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final CollectionGroup group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with TickerProviderStateMixin {
  final _groupService = GroupService();
  final _tagService = TagService();
  final _collectionSearch = TextEditingController();
  final _wishlistSearch = TextEditingController();
  late CollectionGroup _group;
  late final Stream<List<Map<String, dynamic>>> _stream;
  late final TabController _scopeTabController;
  /// Les objets du groupe ont tous un `group_id` : éviter le filtre « Personnel » par défaut.
  late CollectionListFilters _collectionFilters;
  late CollectionListFilters _wishlistFilters;
  CollectionViewMode _viewMode = CollectionViewMode.grid;
  CollectionCategory _selectedCategory = CollectionCategory.boardgame;
  bool _categorySynced = false;
  List<StorageLocation> _locations = [];
  List<ItemTag> _tags = [];

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _collectionFilters = CollectionListFilters(
      ownershipView: CollectionOwnershipView.groups,
      groupIds: {_group.id},
    );
    _wishlistFilters = CollectionListFilters(
      ownershipView: CollectionOwnershipView.groups,
      groupIds: {_group.id},
    );
    _scopeTabController = TabController(length: 2, vsync: this);
    _stream = Supabase.instance.client
        .from('collection_items')
        .stream(primaryKey: ['id'])
        .eq('group_id', _group.id);
    _loadFilterData();
  }

  @override
  void dispose() {
    _scopeTabController.dispose();
    _collectionSearch.dispose();
    _wishlistSearch.dispose();
    super.dispose();
  }

  Future<void> _loadFilterData() async {
    try {
      final locs = await LocationService().fetchLocations(groupId: _group.id);
      final tags = await _tagService.fetchMyTags();
      if (mounted) {
        setState(() {
          _locations = locs;
          _tags = tags;
        });
      }
    } catch (_) {}
  }

  Future<void> _openEdit() async {
    final updated = await Navigator.push<CollectionGroup>(
      context,
      MaterialPageRoute(
        builder: (ctx) => GroupEditScreen(group: _group),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _group = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ProfileAvatar.colorFromHex(_group.accentColor);
    final canEdit = _groupService.canEdit(_group);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            GroupBadge.fromGroup(
              name: _group.name,
              avatarUrl: _group.avatarUrl,
              accentColor: _group.accentColor,
              iconKey: _group.iconKey,
              radius: 18,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(_group.name)),
          ],
        ),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Membres',
            onPressed: () => showGroupMembersSheet(
              context,
              groupId: _group.id,
              groupName: _group.name,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.grid_view_rounded),
            tooltip: 'Collections',
            onPressed: () => AppNavigation.openCollections(context),
          ),
          IconButton(
            icon: Icon(
              _viewMode == CollectionViewMode.grid
                  ? Icons.view_list
                  : Icons.grid_view,
            ),
            onPressed: () => setState(() {
              _viewMode = _viewMode == CollectionViewMode.grid
                  ? CollectionViewMode.list
                  : CollectionViewMode.grid;
            }),
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              tooltip: 'Personnaliser',
              onPressed: _openEdit,
            ),
        ],
        bottom: TabBar(
          controller: _scopeTabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Collection'),
            Tab(text: 'Wishlist'),
          ],
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return FutureBuilder<List<CollectionItem>>(
            future: _tagService.enrichItems(
              snapshot.data!
                  .map((j) => CollectionItem.fromJson(j))
                  .toList(),
            ),
            builder: (context, enriched) {
              final all = enriched.data ?? [];
              final collection = all
                  .where((i) => !i.isWishlist && isActiveCollectionItem(i))
                  .toList();
              final wishlist = all.where((i) => i.isWishlist).toList();
              _pickInitialCategory(collection);

              return Column(
                children: [
                  GroupStatsBanner(
                    collectionItems: collection,
                    wishlistItems: wishlist,
                    accent: accent,
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _scopeTabController,
                      children: [
                        _buildScopePane(
                          items: collection,
                          isWishlist: false,
                          filters: _collectionFilters,
                          searchController: _collectionSearch,
                          onFiltersChanged: (f) =>
                              setState(() => _collectionFilters = f),
                          emptyHint: 'Aucun objet partagé dans ce groupe.',
                        ),
                        _buildScopePane(
                          items: wishlist,
                          isWishlist: true,
                          filters: _wishlistFilters,
                          searchController: _wishlistSearch,
                          onFiltersChanged: (f) =>
                              setState(() => _wishlistFilters = f),
                          emptyHint: 'Rien en wishlist pour ce groupe.',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _pickInitialCategory(List<CollectionItem> items) {
    if (_categorySynced || items.isEmpty) return;
    if (items.any((i) => i.category == _selectedCategory)) {
      _categorySynced = true;
      return;
    }
    for (final cat in CollectionCategory.values) {
      if (items.any((i) => i.category == cat)) {
        _categorySynced = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedCategory = cat);
        });
        return;
      }
    }
  }

  Widget _buildScopePane({
    required List<CollectionItem> items,
    required bool isWishlist,
    required CollectionListFilters filters,
    required TextEditingController searchController,
    required ValueChanged<CollectionListFilters> onFiltersChanged,
    required String emptyHint,
  }) {
    final categoryItems =
        items.where((i) => i.category == _selectedCategory).toList();
    final filtered = filters.apply(categoryItems);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollectionFilterBar(
          filters: filters,
          onChanged: onFiltersChanged,
          searchController: searchController,
          locations: _locations,
          tags: _tags,
          showScopeFilters: false,
          showLocationFilter: !isWishlist &&
              _selectedCategory != CollectionCategory.boardgame,
          showTagFilter:
              !isWishlist && _selectedCategory != CollectionCategory.boardgame,
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: CollectionCategory.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final cat = CollectionCategory.values[index];
              final count = items.where((i) => i.category == cat).length;
              final selected = cat == _selectedCategory;
              return FilterChip(
                label: Text(
                  count > 0 ? '${cat.label} ($count)' : cat.label,
                  style: const TextStyle(fontSize: 12),
                ),
                selected: selected,
                onSelected: (_) => setState(() => _selectedCategory = cat),
                avatar: Icon(cat.icon, size: 16),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            _countLabel(categoryItems, filtered),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: _viewMode == CollectionViewMode.grid
              ? _buildGrid(
                  filtered,
                  _selectedCategory,
                  emptyHint,
                  filters,
                )
              : _buildList(
                  filtered,
                  _selectedCategory,
                  emptyHint,
                  filters,
                ),
        ),
      ],
    );
  }

  String _countLabel(List<CollectionItem> items, List<CollectionItem> filtered) {
    if (filtered.length != items.length) {
      return '${filtered.length} sur ${items.length}';
    }
    return '${items.length} objet${items.length > 1 ? 's' : ''}';
  }

  Widget _buildGrid(
    List<CollectionItem> items,
    CollectionCategory category,
    String emptyHint,
    CollectionListFilters filters,
  ) {
    final grouped = CollectionGridGrouper.group(items);
    if (grouped.isEmpty) {
      return Center(
        child: Text(
          filters.hasActiveFilters
              ? 'Aucun objet ne correspond aux filtres.'
              : emptyHint,
          style: TextStyle(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Builder(
      builder: (context) {
        final grid = GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: CollectionGridLayout.crossAxisCount(context),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio:
                CollectionGridLayout.aspectRatio(category, context),
          ),
          itemCount: grouped.length,
          itemBuilder: (context, index) {
            final entry = grouped[index];
            final item = entry.item;

            return CollectionItemTile(
              item: item,
              category: category,
              totalQuantity: entry.totalQuantity,
              showDuplicateBadge: entry.hasDuplicates,
              showGroupBadge: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ItemDetailScreen(
                    item: item.copyWith(quantity: entry.totalQuantity),
                  ),
                ),
              ),
            );
          },
        );

        return CollectionGridLayout.constrainOnWebDesktop(
          context: context,
          child: grid,
        );
      },
    );
  }

  Widget _buildList(
    List<CollectionItem> items,
    CollectionCategory category,
    String emptyHint,
    CollectionListFilters filters,
  ) {
    final grouped = CollectionGridGrouper.group(items);
    if (grouped.isEmpty) {
      return Center(
        child: Text(
          filters.hasActiveFilters
              ? 'Aucun objet ne correspond aux filtres.'
              : emptyHint,
          style: TextStyle(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final entry = grouped[index];
        final item = entry.item;
        return CollectionItemListTile(
          item: item,
          category: category,
          totalQuantity: entry.totalQuantity,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => ItemDetailScreen(
                item: item.copyWith(quantity: entry.totalQuantity),
              ),
            ),
          ),
        );
      },
    );
  }
}
