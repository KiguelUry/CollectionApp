import 'package:flutter/material.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../collection_cover_image.dart';

/// Vitrine horizontale de favoris (style Letterboxd).
class FavoritesShowcase extends StatelessWidget {
  final List<CollectionItem?> slots;
  final Color accentColor;
  final bool editable;
  final void Function(int index)? onSlotTap;

  const FavoritesShowcase({
    super.key,
    required this.slots,
    required this.accentColor,
    this.editable = false,
    this.onSlotTap,
  });

  static const _coverWidth = 88.0;
  static const _coverHeight = 132.0;
  static const _radius = 16.0;

  @override
  Widget build(BuildContext context) {
    final items = List<CollectionItem?>.generate(
      6,
      (i) => i < slots.length ? slots[i] : null,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.55),
          ],
        ),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vitrine de favoris',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: accentColor.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tes 6 coups de cœur — visibles par tes amis.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: _coverHeight + 8,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 6,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _FavoriteSlot(
                      item: item,
                      editable: editable,
                      onTap: editable ? () => onSlotTap?.call(index) : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteSlot extends StatelessWidget {
  final CollectionItem? item;
  final bool editable;
  final VoidCallback? onTap;

  const _FavoriteSlot({
    required this.item,
    required this.editable,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: FavoritesShowcase._coverWidth,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FavoritesShowcase._radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FavoritesShowcase._radius),
        child: item != null &&
                item!.imageUrl != null &&
                item!.imageUrl!.isNotEmpty
            ? CollectionCoverImage(
                url: item!.imageUrl!,
                width: FavoritesShowcase._coverWidth,
                height: FavoritesShowcase._coverHeight,
                bookCover: item!.category == CollectionCategory.book,
                fit: BoxFit.cover,
              )
            : Container(
                width: FavoritesShowcase._coverWidth,
                height: FavoritesShowcase._coverHeight,
                color: Colors.grey.shade200,
                child: Icon(
                  editable ? Icons.add_rounded : Icons.star_outline,
                  color: Colors.grey.shade500,
                  size: 32,
                ),
              ),
      ),
    );

    if (!editable || onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FavoritesShowcase._radius),
        child: child,
      ),
    );
  }
}
