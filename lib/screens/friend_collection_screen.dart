import 'package:flutter/material.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/friend_service.dart';
import '../utils/collection_grid_grouper.dart';
import '../widgets/collection_item_tile.dart';
import '../widgets/profile_avatar.dart';
import 'item_detail_screen.dart';

/// Collection d'un ami (lecture seule si partage activé).
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

class _FriendCollectionScreenState extends State<FriendCollectionScreen> {
  final _friendService = FriendService();
  List<CollectionItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.shareCollections) {
      setState(() {
        _loading = false;
        _items = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _items = await _friendService.fetchFriendCollectionItems(
        widget.profileId,
      );
    } catch (e) {
      _items = [];
      _error = e.toString();
    }

    if (mounted) setState(() => _loading = false);
  }

  int _countFor(CollectionCategory category) =>
      _items.where((i) => i.category == category).length;

  @override
  Widget build(BuildContext context) {
    final accent = ProfileAvatar.colorFromHex(widget.accentColor);

    return DefaultTabController(
      length: CollectionCategory.values.length,
      child: Scaffold(
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
                    Text(
                      widget.shareCollections
                          ? 'Collection partagée'
                          : 'Collection privée',
                      style: const TextStyle(
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
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: CollectionCategory.values.map((c) {
              final n = _countFor(c);
              return Tab(
                text: n > 0 ? '${c.label} ($n)' : c.label,
              );
            }).toList(),
          ),
        ),
        body: !widget.shareCollections
            ? _buildPrivate()
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : TabBarView(
                        children: CollectionCategory.values
                            .map(_buildCategoryGrid)
                            .toList(),
                      ),
      ),
    );
  }

  Widget _buildPrivate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '${widget.username} ne partage pas sa collection',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Le partage doit être activé dans votre amitié '
              '(interrupteur « Collections partagées »).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid(CollectionCategory category) {
    final items =
        _items.where((i) => i.category == category).toList();
    if (items.isEmpty) {
      return const Center(child: Text('Rien dans cette catégorie.'));
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
          category: category,
          totalQuantity: entry.totalQuantity,
          showDuplicateBadge: entry.hasDuplicates,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => ItemDetailScreen(
                item: item.copyWith(quantity: entry.totalQuantity),
                readOnly: true,
              ),
            ),
          ),
        );
      },
    );
  }
}
