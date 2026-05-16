import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../widgets/add_game_options_dialog.dart';
import '../widgets/add_item_manual_dialog.dart';
import '../widgets/bgg_network_image.dart';
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
  late final Stream<List<Map<String, dynamic>>> _itemsStream;

  @override
  void initState() {
    super.initState();
    _itemsStream = Supabase.instance.client
        .from('collection_items')
        .stream(primaryKey: ['id'])
        .eq('category', widget.category.dbValue);
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
          imageUrl: null,
          minPlayers: null,
          maxPlayers: null,
          playingTime: null,
          bggId: bggGame['id'],
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
    int? minPlayers,
    int? maxPlayers,
    int? playingTime,
    String? bggId,
    bool closesTwoDialogs = false,
  }) {
    showDialog(
      context: context,
      builder: (context) => AddGameOptionsDialog(
        gameTitle: title,
        onConfirm: (isWishlist, selectedUser) async {
          await _handleSave(
            title: title,
            isWishlist: isWishlist,
            profileId: selectedUser,
            imageUrl: imageUrl,
            minPlayers: minPlayers,
            maxPlayers: maxPlayers,
            playingTime: playingTime,
            bggId: bggId,
            subcategory: subcategory,
            metadata: metadata,
            closesTwoDialogs: closesTwoDialogs,
          );
        },
      ),
    );
  }

  Future<void> _handleSave({
    required String title,
    required bool isWishlist,
    String? profileId,
    String? imageUrl,
    String? subcategory,
    Map<String, dynamic>? metadata,
    int? minPlayers,
    int? maxPlayers,
    int? playingTime,
    String? bggId,
    bool closesTwoDialogs = false,
  }) async {
    String? resolvedImageUrl = imageUrl;
    int? resolvedMin = minPlayers;
    int? resolvedMax = maxPlayers;
    int? resolvedTime = playingTime;

    if (bggId != null) {
      final details = await BggService.getGameFullDetails(bggId);
      resolvedImageUrl = details?['image_url'] as String?;
      resolvedMin = details?['min_players'] as int?;
      resolvedMax = details?['max_players'] as int?;
      resolvedTime = details?['playing_time'] as int?;
    }

    final item = CollectionItem(
      id: '',
      title: title,
      category: widget.category,
      subcategory: subcategory,
      metadata: metadata,
      imageUrl: resolvedImageUrl,
      isWishlist: isWishlist,
      minPlayers: resolvedMin,
      maxPlayers: resolvedMax,
      playingTime: resolvedTime,
    );

    await Supabase.instance.client.from('collection_items').insert(
          item.toInsertJson(isWishlist: isWishlist, locationUserId: profileId),
        );

    if (mounted) {
      Navigator.pop(context);
      if (closesTwoDialogs || bggId != null) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.category.label),
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

            final allItems = snapshot.data!
                .map((json) => CollectionItem.fromJson(json))
                .toList();
            final collection =
                allItems.where((item) => !item.isWishlist).toList();
            final wishlist =
                allItems.where((item) => item.isWishlist).toList();

            return TabBarView(
              children: [
                _buildItemGrid(collection),
                _buildItemGrid(wishlist),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildItemGrid(List<CollectionItem> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Aucun objet ici.'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ItemDetailScreen(item: item),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: item.imageUrl != null
                        ? BggNetworkImage(url: item.imageUrl!)
                        : Container(
                            color: Colors.grey.shade200,
                            child: Icon(
                              widget.category.icon,
                              color: Colors.grey,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      item.listSubtitle ?? '',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
