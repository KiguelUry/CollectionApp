import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';

/// Bandeau récap pour un groupe (totaux + catégories actives).
class GroupStatsBanner extends StatelessWidget {
  final List<CollectionItem> collectionItems;
  final List<CollectionItem> wishlistItems;
  final Color accent;

  const GroupStatsBanner({
    super.key,
    required this.collectionItems,
    required this.wishlistItems,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cats = <CollectionCategory>{};
    for (final i in collectionItems) {
      cats.add(i.category);
    }
    for (final i in wishlistItems) {
      cats.add(i.category);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${collectionItems.length} objet${collectionItems.length > 1 ? 's' : ''}'
                  '${wishlistItems.isNotEmpty ? ' · ${wishlistItems.length} wishlist' : ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (cats.isNotEmpty)
                  Text(
                    cats.map((c) => c.label).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
