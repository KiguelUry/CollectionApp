import 'package:flutter/material.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../collection_cover_image.dart';

/// Vitrine fixe 3×2 (style Letterboxd / podium).
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

  static const _radius = 14.0;

  @override
  Widget build(BuildContext context) {
    final items = List<CollectionItem?>.generate(
      6,
      (i) => i < slots.length ? slots[i] : null,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  accentColor.withValues(alpha: 0.22),
                  const Color(0xFF1A1A22),
                ]
              : [
                  accentColor.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.55),
                ],
        ),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
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
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 10.0;
                  const rows = 2;
                  const cols = 3;
                  final cellW = (constraints.maxWidth - gap * (cols - 1)) / cols;
                  final cellH = cellW * 1.45;
                  return Column(
                    children: [
                      for (var row = 0; row < rows; row++) ...[
                        if (row > 0) const SizedBox(height: gap),
                        Row(
                          children: [
                            for (var col = 0; col < cols; col++) ...[
                              if (col > 0) const SizedBox(width: gap),
                              Expanded(
                                child: SizedBox(
                                  height: cellH,
                                  child: _FavoriteSlot(
                                    item: items[row * cols + col],
                                    editable: editable,
                                    radius: _radius,
                                    onTap: editable
                                        ? () => onSlotTap?.call(row * cols + col)
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  );
                },
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
  final double radius;
  final VoidCallback? onTap;

  const _FavoriteSlot({
    required this.item,
    required this.editable,
    required this.radius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: item != null &&
                item!.imageUrl != null &&
                item!.imageUrl!.isNotEmpty
            ? LayoutBuilder(
                builder: (context, c) => CollectionCoverImage(
                  url: item!.imageUrl!,
                  width: c.maxWidth,
                  height: c.maxHeight,
                  bookCover: item!.category == CollectionCategory.book,
                  fit: BoxFit.cover,
                ),
              )
            : ColoredBox(
                color: Colors.grey.shade200,
                child: Center(
                  child: Icon(
                    editable ? Icons.add_rounded : Icons.star_outline,
                    color: Colors.grey.shade500,
                    size: 28,
                  ),
                ),
              ),
      ),
    );

    if (!editable || onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}
