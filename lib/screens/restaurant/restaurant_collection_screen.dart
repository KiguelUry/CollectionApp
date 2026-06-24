import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../../widgets/category_hub_header.dart';
import '../../widgets/collection_item_tile.dart';
import 'restaurant_map_screen.dart';
import 'restaurant_search_screen.dart';
import '../item_detail_screen.dart';

/// Hub journal culinaire (onglets visités / wishlist).
class RestaurantCollectionScreen extends StatefulWidget {
  const RestaurantCollectionScreen({super.key});

  @override
  State<RestaurantCollectionScreen> createState() =>
      _RestaurantCollectionScreenState();
}

class _RestaurantCollectionScreenState extends State<RestaurantCollectionScreen>
    with SingleTickerProviderStateMixin {
  static final _accent = CollectionCategory.restaurant.color;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          CategoryHubHeader(
            title: 'Restaurants',
            accentColor: _accent,
            trailingActions: [
              IconButton(
                icon: Icon(Icons.map_outlined, color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RestaurantMapScreen(),
                  ),
                ),
              ),
            ],
            tabBar: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Déjà faits'),
                Tab(text: 'À tester'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _RestaurantListTab(wishlist: false),
                _RestaurantListTab(wishlist: true),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RestaurantSearchScreen(),
          ),
        ),
        backgroundColor: _accent,
        icon: const Icon(Icons.search),
        label: const Text('Chercher un resto'),
      ),
    );
  }
}

class _RestaurantListTab extends StatelessWidget {
  final bool wishlist;

  const _RestaurantListTab({required this.wishlist});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final stream = Supabase.instance.client
        .from('collection_items')
        .stream(primaryKey: ['id'])
        .eq('category', CollectionCategory.restaurant.dbValue);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!
            .map((r) => CollectionItem.fromJson(r))
            .where((i) {
          final mine = i.addedBy == userId || i.locationUserId == userId;
          return mine && i.isWishlist == wishlist && !i.isSold;
        }).toList();

        if (items.isEmpty) {
          return Center(
            child: Text(
              wishlist ? 'Aucun resto en wishlist.' : 'Aucune visite enregistrée.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.75,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            return CollectionItemTile(
              item: item,
              category: CollectionCategory.restaurant,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ItemDetailScreen(item: item),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
