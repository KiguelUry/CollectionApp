import 'package:flutter/material.dart';

import '../models/book_author_group.dart';
import '../models/collection_item.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/author_avatar.dart';
import '../widgets/collection_cover_image.dart';
import 'book_series_detail_screen.dart';
import 'item_detail_screen.dart';

class BookAuthorDetailScreen extends StatelessWidget {
  final BookAuthorGroup group;

  const BookAuthorDetailScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final owned = group.items.where((i) => !i.isWishlist && !i.isSold).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    final wishlist = group.items.where((i) => i.isWishlist).toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    return Scaffold(
      appBar: AppAppBar(title: group.author),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AuthorAvatar(authorName: group.author, radius: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.author,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${group.ownedCount} possédé(s) · '
                          '${wishlist.length} wishlist · '
                          '${group.totalCount} entrée(s)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (owned.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                'Dans ma collection',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...owned.map((item) => _BookTile(item: item)),
          ],
          if (wishlist.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                'Wishlist',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...wishlist.map((item) => _BookTile(item: item)),
          ],
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final CollectionItem item;

  const _BookTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: item.imageUrl != null && item.imageUrl!.isNotEmpty
            ? SizedBox(
                width: 40,
                height: 58,
                child: CollectionCoverImage(
                  url: item.imageUrl!,
                  width: 40,
                  height: 58,
                  bookCover: true,
                ),
              )
            : const Icon(Icons.menu_book_outlined),
        title: Text(item.title),
        subtitle: Text(item.listSubtitle ?? ''),
        trailing: item.seriesId != null
            ? const Icon(Icons.auto_stories_outlined, size: 20)
            : null,
        onTap: () async {
          if (item.seriesId != null) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) =>
                    BookSeriesDetailScreen(seriesId: item.seriesId!),
              ),
            );
          } else {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => ItemDetailScreen(item: item),
              ),
            );
          }
        },
      ),
    );
  }
}
