import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_item_filters.dart';
import '../utils/collection_item_scope.dart';
import '../models/collection_list_filters.dart';
import '../models/collection_view_mode.dart';
import '../models/item_tag.dart';
import '../models/storage_location.dart';
import '../services/location_service.dart';
import '../services/open_library_service.dart';
import '../services/tag_service.dart';
import '../widgets/collection_filter_bar.dart';
import '../widgets/collection_item_list_tile.dart';
import '../widgets/collection_item_tile.dart';
import '../widgets/isbn_scan_sheet.dart';
import 'shake_pick_screen.dart';
import '../widgets/add_item_manual_dialog.dart';
import '../widgets/add_item_options_dialog.dart';
import '../widgets/bgg_search_dialog.dart';
import '../widgets/book_search_dialog.dart';
import '../widgets/main_drawer.dart';
import 'item_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  final CollectionCategory category;

  const HomeScreen({super.key, required this.category});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tagService = TagService();
  final _collectionSearch = TextEditingController();
  final _wishlistSearch = TextEditingController();

  late final String _userId;
  late final Stream<List<Map<String, dynamic>>> _itemsStream;
  CollectionListFilters _collectionFilters = CollectionListFilters();
  CollectionListFilters _wishlistFilters = CollectionListFilters();
  CollectionViewMode _viewMode = CollectionViewMode.grid;
  List<StorageLocation> _locations = [];
  List<ItemTag> _tags = [];

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser!.id;
    final rawStream = Supabase.instance.client
        .from('collection_items')
        .stream(primaryKey: ['id'])
        .eq('category', widget.category.dbValue);
    _itemsStream = rawStream.map(_onlyMyRows);
    _loadFilterData();
  }

  @override
  void dispose() {
    _collectionSearch.dispose();
    _wishlistSearch.dispose();
    super.dispose();
  }

  Future<void> _loadFilterData() async {
    try {
      final locs = await LocationService().fetchLocations();
      final tags = await _tagService.fetchMyTags();
      if (mounted) {
        setState(() {
          _locations = locs;
          _tags = tags;
        });
      }
    } catch (_) {}
  }

  Future<void> _scanIsbnAndAdd() async {
    final isbn = await showIsbnScanSheet(context);
    if (isbn == null || !mounted) return;

    final book = await OpenLibraryService.lookupByIsbn(isbn);
    if (!mounted) return;
    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Livre introuvable pour cet ISBN')),
      );
      return;
    }

    _showOptionsDialog(
      title: book['title']!,
      imageUrl: book['image_url']?.isNotEmpty == true ? book['image_url'] : null,
      subcategory: 'book',
    );
  }

  List<Map<String, dynamic>> _onlyMyRows(List<Map<String, dynamic>> rows) {
    return rows.where((row) {
      final addedBy = row['added_by'] as String?;
      final locUser = row['location_user_id'] as String?;
      return addedBy == _userId || locUser == _userId;
    }).toList();
  }

  void _onAddPressed() {
    if (widget.category.supportsBggSearch) {
      _showBggSearchDialog();
    } else if (widget.category.supportsOpenLibrarySearch) {
      _showBookSearchDialog();
    } else {
      _showManualAddFlow();
    }
  }

  void _showBggSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => BggSearchDialog(
        onGameSelected: (bggGame) => _showOptionsDialog(
          title: bggGame['title']!,
          bggId: bggGame['id'],
          imageUrl: bggGame['image_url'],
          closesTwoDialogs: true,
        ),
      ),
    );
  }

  void _showBookSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => BookSearchDialog(
        onBookSelected: (book, subcategory) => _showOptionsDialog(
          title: book['title']!,
          imageUrl: book['image_url']!.isEmpty ? null : book['image_url'],
          subcategory: subcategory.dbValue,
          closesTwoDialogs: true,
        ),
      ),
    );
  }

  Future<void> _showManualAddFlow() async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddItemManualDialog(
        categoryLabel: widget.category.label,
        category: widget.category,
      ),
    );
    if (draft == null || !mounted) return;

    _showOptionsDialog(
      title: draft['title'] as String,
      imageUrl: draft['image_url'] as String?,
      subcategory: draft['subcategory'] as String?,
      metadata: draft['metadata'] as Map<String, dynamic>?,
    );
  }

  void _showOptionsDialog({
    required String title,
    String? imageUrl,
    String? subcategory,
    Map<String, dynamic>? metadata,
    String? bggId,
    bool closesTwoDialogs = false,
  }) {
    showDialog(
      context: context,
      builder: (context) => AddItemOptionsDialog(
        itemTitle: title,
        onConfirm: (options) async {
          await _handleSave(
            title: title,
            options: options,
            imageUrl: imageUrl,
            subcategory: subcategory,
            metadata: metadata,
            bggId: bggId,
            closesTwoDialogs: closesTwoDialogs,
          );
        },
      ),
    );
  }

  Future<void> _handleSave({
    required String title,
    required AddItemOptions options,
    String? imageUrl,
    String? subcategory,
    Map<String, dynamic>? metadata,
    String? bggId,
    bool closesTwoDialogs = false,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    String? resolvedImageUrl = imageUrl;
    int? resolvedMin;
    int? resolvedMax;
    int? resolvedTime;

    if (bggId != null) {
      final details = await BggService.getGameFullDetails(bggId);
      resolvedImageUrl =
          (details?['image_url'] as String?) ?? resolvedImageUrl;
      resolvedMin = details?['min_players'] as int?;
      resolvedMax = details?['max_players'] as int?;
      resolvedTime = details?['playing_time'] as int?;
    }

    // Fusionner les doublons (même titre + catégorie + groupe)
    var dupQuery = client
        .from('collection_items')
        .select('id, quantity')
        .eq('category', widget.category.dbValue)
        .eq('title', title.trim());

    if (options.groupId != null) {
      dupQuery = dupQuery.eq('group_id', options.groupId!);
    } else {
      dupQuery = dupQuery
          .filter('group_id', 'is', null)
          .or(CollectionItemScope.personalOrFilter(userId));
    }

    final existing = await dupQuery.maybeSingle();
    if (existing != null) {
      final newQty = ((existing['quantity'] as int?) ?? 1) + options.quantity;
      await client
          .from('collection_items')
          .update({'quantity': newQty})
          .eq('id', existing['id']);
    } else {
      final item = CollectionItem(
        id: '',
        title: title.trim(),
        category: widget.category,
        subcategory: subcategory,
        metadata: metadata,
        imageUrl: resolvedImageUrl,
        isWishlist: options.isWishlist,
        quantity: options.quantity,
        locationId: options.locationId,
        groupId: options.groupId,
        minPlayers: resolvedMin,
        maxPlayers: resolvedMax,
        playingTime: resolvedTime,
      );

      await client.from('collection_items').insert(
            item.toInsertJson(
              isWishlist: options.isWishlist,
              locationUserId: options.isWishlist
                  ? null
                  : (options.locationUserId ?? userId),
              addedBy: userId,
            ),
          );
    }

    if (mounted) {
      Navigator.pop(context);
      if (closesTwoDialogs) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.category.label),
          actions: [
            IconButton(
              icon: Icon(
                _viewMode == CollectionViewMode.grid
                    ? Icons.view_list
                    : Icons.grid_view,
              ),
              tooltip: _viewMode == CollectionViewMode.grid
                  ? 'Vue liste'
                  : 'Vue grille',
              onPressed: () => setState(() {
                _viewMode = _viewMode == CollectionViewMode.grid
                    ? CollectionViewMode.list
                    : CollectionViewMode.grid;
              }),
            ),
            if (widget.category.supportsOpenLibrarySearch)
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Scanner ISBN',
                onPressed: _scanIsbnAndAdd,
              ),
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: 'Shake to Pick',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ShakePickScreen(category: widget.category),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.deepPurple,
            tabs: [
              Tab(text: 'Collection'),
              Tab(text: 'Wishlist'),
            ],
          ),
        ),
        drawer: const MainDrawer(),
        floatingActionButton: FloatingActionButton(
          onPressed: _onAddPressed,
          child: const Icon(Icons.add),
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _itemsStream,
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
                    .map((json) => CollectionItem.fromJson(json))
                    .toList(),
              ),
              builder: (context, enrichedSnap) {
                final allItems = enrichedSnap.data ??
                    snapshot.data!
                        .map((json) => CollectionItem.fromJson(json))
                        .toList();
                final collection = allItems
                    .where((item) =>
                        !item.isWishlist && isActiveCollectionItem(item))
                    .toList();
                final wishlist =
                    allItems.where((item) => item.isWishlist).toList();

                return TabBarView(
                  children: [
                    _buildTab(
                      items: collection,
                      filters: _collectionFilters,
                      searchController: _collectionSearch,
                      onFiltersChanged: (f) =>
                          setState(() => _collectionFilters = f),
                      emptyHint: 'Ta collection est vide ici.',
                      showScopeFilters: true,
                    ),
                    _buildTab(
                      items: wishlist,
                      filters: _wishlistFilters,
                      searchController: _wishlistSearch,
                      onFiltersChanged: (f) =>
                          setState(() => _wishlistFilters = f),
                      emptyHint: 'Rien en wishlist pour cette catégorie.',
                      showScopeFilters: false,
                      showStatusFilters: false,
                      showLocationFilter: false,
                      showTagFilter: false,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildTab({
    required List<CollectionItem> items,
    required CollectionListFilters filters,
    required TextEditingController searchController,
    required ValueChanged<CollectionListFilters> onFiltersChanged,
    required String emptyHint,
    bool showScopeFilters = true,
    bool showStatusFilters = true,
    bool showLocationFilter = true,
    bool showTagFilter = true,
  }) {
    final filtered = filters.apply(items);
    final countLabel = filtered.length == items.length
        ? '${items.length} objet${items.length > 1 ? 's' : ''}'
        : '${filtered.length} sur ${items.length}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollectionFilterBar(
          filters: filters,
          onChanged: onFiltersChanged,
          searchController: searchController,
          locations: _locations,
          tags: _tags,
          showScopeFilters: showScopeFilters,
          showStatusFilters: showStatusFilters,
          showLocationFilter: showLocationFilter,
          showTagFilter: showTagFilter,
        ),
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
          child: _viewMode == CollectionViewMode.grid
              ? _buildItemGrid(
                  filtered,
                  emptyHint: emptyHint,
                  filters: filters,
                  onClearFilters: () {
                    searchController.clear();
                    onFiltersChanged(CollectionListFilters());
                  },
                )
              : _buildItemList(
                  filtered,
                  emptyHint: emptyHint,
                  filters: filters,
                  onClearFilters: () {
                    searchController.clear();
                    onFiltersChanged(CollectionListFilters());
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildItemGrid(
    List<CollectionItem> items, {
    required String emptyHint,
    required CollectionListFilters filters,
    required VoidCallback onClearFilters,
  }) {
    if (items.isEmpty) {
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
                emptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (filters.hasActiveFilters) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onClearFilters,
                  child: const Text('Réinitialiser les filtres'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final grouped = CollectionGridGrouper.group(items);

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
          category: widget.category,
          totalQuantity: entry.totalQuantity,
          showDuplicateBadge: entry.hasDuplicates,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ItemDetailScreen(
                item: item.copyWith(quantity: entry.totalQuantity),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemList(
    List<CollectionItem> items, {
    required String emptyHint,
    required CollectionListFilters filters,
    required VoidCallback onClearFilters,
  }) {
    if (items.isEmpty) {
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
                emptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (filters.hasActiveFilters) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onClearFilters,
                  child: const Text('Réinitialiser les filtres'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final grouped = CollectionGridGrouper.group(items);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final entry = grouped[index];
        final item = entry.item;
        return CollectionItemListTile(
          item: item,
          category: widget.category,
          totalQuantity: entry.totalQuantity,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ItemDetailScreen(
                item: item.copyWith(quantity: entry.totalQuantity),
              ),
            ),
          ),
        );
      },
    );
  }
}
