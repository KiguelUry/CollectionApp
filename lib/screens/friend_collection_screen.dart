import 'package:flutter/material.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/friend_service.dart';
import '../utils/collection_grid_grouper.dart';
import '../navigation/app_navigation.dart';
import '../utils/copy_friend_item.dart';
import '../utils/friend_item_overlap.dart';
import '../widgets/collection_item_tile.dart';
import '../widgets/profile_avatar.dart';
import 'item_detail_screen.dart';

/// Collection et wishlist d'un ami (lecture seule).
class FriendCollectionScreen extends StatefulWidget {
  final String profileId;
  final String username;
  final String? avatarUrl;
  final String? accentColor;
  final bool shareCollections;

  const FriendCollectionScreen({
    super.key,
    required this.profileId,
    required this.username,
    this.avatarUrl,
    this.accentColor,
    required this.shareCollections,
  });

  @override
  State<FriendCollectionScreen> createState() => _FriendCollectionScreenState();
}

class _FriendCollectionScreenState extends State<FriendCollectionScreen>
    with SingleTickerProviderStateMixin {
  final _friendService = FriendService();
  late final TabController _scopeTabController;
  List<CollectionItem> _collectionItems = [];
  List<CollectionItem> _wishlistItems = [];
  bool? _wishlistShared;
  bool _loading = true;
  String? _error;
  CollectionCategory _selectedCategory = CollectionCategory.boardgame;
  FriendOverlapIndex? _overlap;
  bool _categorySynced = false;

  @override
  void initState() {
    super.initState();
    _scopeTabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _scopeTabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (!widget.shareCollections) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Collections non partagées. Active « Collections partagées » '
              'dans le menu de cet ami.';
        });
      }
      return;
    }

    try {
      _collectionItems = await _friendService.fetchFriendCollectionItems(
        widget.profileId,
      );
      _wishlistShared = await _friendService.canViewFriendWishlist(
        widget.profileId,
      );
      if (_wishlistShared == true) {
        _wishlistItems = await _friendService.fetchFriendWishlistItems(
          widget.profileId,
        );
      } else {
        _wishlistItems = [];
      }
      _overlap = await buildFriendOverlapIndex([
        ..._collectionItems,
        ..._wishlistItems,
      ]);
      _categorySynced = false;
    } catch (e) {
      _collectionItems = [];
      _wishlistItems = [];
      _overlap = null;
      _error = e.toString();
    }

    if (mounted) {
      setState(() => _loading = false);
      _pickInitialCategory([..._collectionItems, ..._wishlistItems]);
    }
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
        setState(() => _selectedCategory = cat);
        return;
      }
    }
  }

  Widget? _overlapBanner() {
    final o = _overlap;
    if (o == null || (o.inCollectionCount == 0 && o.inWishlistCount == 0)) {
      return null;
    }
    final parts = <String>[];
    if (o.inCollectionCount > 0) {
      parts.add(
        '${o.inCollectionCount} en commun',
      );
    }
    if (o.inWishlistCount > 0) {
      parts.add('${o.inWishlistCount} dans ta wishlist');
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, color: Colors.teal.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.teal.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<CollectionItem> _itemsForScope(bool wishlist) =>
      wishlist ? _wishlistItems : _collectionItems;

  int _countFor(CollectionCategory category, bool wishlist) =>
      _itemsForScope(wishlist)
          .where((i) => i.category == category)
          .length;

  @override
  Widget build(BuildContext context) {
    final accent = ProfileAvatar.colorFromHex(widget.accentColor);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ProfileAvatar(
              avatarUrl: widget.avatarUrl,
              accentColorHex: widget.accentColor,
              fallbackInitial: widget.username,
              radius: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.username),
                  const Text(
                    'Collection',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Appui long sur un objet pour l\'ajouter chez toi',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Appui long sur une vignette → ajouter à ta collection ou wishlist',
                  ),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.grid_view_rounded),
            tooltip: 'Collections',
            onPressed: () => AppNavigation.openCollections(context),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _scopeTabController,
                  children: [
                    _buildScopePane(wishlist: false),
                    _buildScopePane(wishlist: true),
                  ],
                ),
    );
  }

  Widget _buildScopePane({required bool wishlist}) {
    if (wishlist && _wishlistShared == false) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                '${widget.username} ne partage pas sa wishlist',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final overlapBanner = !wishlist ? _overlapBanner() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overlapBanner != null) overlapBanner,
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: CollectionCategory.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final cat = CollectionCategory.values[index];
              final count = _countFor(cat, wishlist);
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
        Expanded(child: _buildCategoryGrid(_selectedCategory, wishlist)),
      ],
    );
  }

  Widget _buildCategoryGrid(CollectionCategory category, bool wishlist) {
    final items = _itemsForScope(wishlist)
        .where((i) => i.category == category)
        .toList();
    if (items.isEmpty) {
      return Center(
        child: Text(
          wishlist
              ? 'Rien en wishlist dans cette catégorie.'
              : 'Rien dans cette catégorie.',
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

        final overlap = _overlap?.kindFor(item);

        return CollectionItemTile(
          item: item,
          category: category,
          totalQuantity: entry.totalQuantity,
          showDuplicateBadge: entry.hasDuplicates,
          overlapKind: overlap,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => ItemDetailScreen(
                item: item.copyWith(quantity: entry.totalQuantity),
                readOnly: true,
                friendUsername: widget.username,
                friendOverlap: overlap,
              ),
            ),
          ),
          onLongPress: () => showCopyFriendItemSheet(
            context,
            source: item,
            friendUsername: widget.username,
          ),
        );
      },
    );
  }
}
