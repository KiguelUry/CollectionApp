import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../widgets/bgg_network_image.dart';
import 'item_detail_screen.dart';

/// Wishlist livres uniquement (onglet du hub livres).
class BookWishlistTab extends StatefulWidget {
  const BookWishlistTab({super.key});

  @override
  State<BookWishlistTab> createState() => _BookWishlistTabState();
}

class _BookWishlistTabState extends State<BookWishlistTab> {
  late final String _userId;
  late final Stream<List<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser!.id;
    _stream = Supabase.instance.client
        .from('collection_items')
        .stream(primaryKey: ['id'])
        .eq('category', 'book')
        .map((rows) => rows.where((row) {
              if (row['is_wishlist'] != true) return false;
              final addedBy = row['added_by'] as String?;
              final locUser = row['location_user_id'] as String?;
              return addedBy == _userId || locUser == _userId;
            }).toList());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!
            .map((j) => CollectionItem.fromJson(j))
            .toList();
        if (items.isEmpty) {
          return const Center(
            child: Text('Aucun livre en wishlist'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final item = items[i];
            return ListTile(
              leading: item.imageUrl != null && item.imageUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 40,
                        height: 56,
                        child: BggNetworkImage(
                          url: item.imageUrl!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  : const Icon(Icons.book_outlined),
              title: Text(item.title),
              subtitle: Text(item.listSubtitle ?? ''),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ItemDetailScreen(item: item),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
