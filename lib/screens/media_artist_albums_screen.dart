import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/collection_grid_grouper.dart';
import '../widgets/collection_item_tile.dart';
import 'item_detail_screen.dart';

/// Albums d'un artiste (vue vinyles / CD).
class MediaArtistAlbumsScreen extends StatelessWidget {
  final String artist;
  final List<CollectionItem> items;

  const MediaArtistAlbumsScreen({
    super.key,
    required this.artist,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = CollectionGridGrouper.group(items);

    return Scaffold(
      appBar: AppBar(title: Text(artist)),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final entry = grouped[index];
          final item = entry.item;
          return CollectionItemTile(
            item: item,
            category: CollectionCategory.media,
            totalQuantity: entry.totalQuantity,
            showDuplicateBadge: entry.hasDuplicates,
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
      ),
    );
  }
}
