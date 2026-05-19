import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../utils/collection_grid_grouper.dart';
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
import 'group_edit_screen.dart';
import 'item_detail_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final CollectionGroup group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final _groupService = GroupService();
  final _tagService = TagService();
  final _searchController = TextEditingController();
  late CollectionGroup _group;
  late final Stream<List<Map<String, dynamic>>> _stream;
  CollectionListFilters _filters = CollectionListFilters();
  CollectionViewMode _viewMode = CollectionViewMode.grid;
  List<StorageLocation> _locations = [];
  List<ItemTag> _tags = [];

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _stream = Supabase.instance.client
        .from('collection_items')
        .stream(primaryKey: ['id'])
        .eq('group_id', _group.id);
    _loadFilterData();
  }

  @override
  void dispose() {
    _searchController.dispose();
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

    return DefaultTabController(
      length: CollectionCategory.values.length,
      child: Scaffold(
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
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: CollectionCategory.values
                .map((c) => Tab(text: c.label))
                .toList(),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CollectionFilterBar(
              filters: _filters,
              onChanged: (f) => setState(() => _filters = f),
              searchController: _searchController,
              locations: _locations,
              tags: _tags,
              showScopeFilters: false,
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
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
                          .where((i) =>
                              !i.isWishlist && isActiveCollectionItem(i))
                          .toList(),
                    ),
                    builder: (context, enriched) {
                      final all = enriched.data ?? [];

                      return TabBarView(
                        children: CollectionCategory.values.map((category) {
                          final items = _filters.apply(
                            all.where((i) => i.category == category).toList(),
                          );
                          final grouped = CollectionGridGrouper.group(items);
                          return _viewMode == CollectionViewMode.grid
                              ? _buildGrid(grouped, category)
                              : _buildList(grouped, category);
                        }).toList(),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(
    List<GroupedCollectionItem> grouped,
    CollectionCategory category,
  ) {
    if (grouped.isEmpty) {
      return Center(
        child: Text(
          _filters.hasActiveFilters
              ? 'Aucun objet ne correspond aux filtres.'
              : 'Aucun objet partagé ici.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
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
  }

  Widget _buildList(
    List<GroupedCollectionItem> grouped,
    CollectionCategory category,
  ) {
    if (grouped.isEmpty) {
      return Center(
        child: Text(
          _filters.hasActiveFilters
              ? 'Aucun objet ne correspond aux filtres.'
              : 'Aucun objet partagé ici.',
          style: TextStyle(color: Colors.grey.shade600),
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
