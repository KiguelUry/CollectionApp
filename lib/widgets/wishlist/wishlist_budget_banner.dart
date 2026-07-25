import 'package:flutter/material.dart';

import '../../models/collection_item.dart';
import '../../utils/wishlist_market_metadata.dart';

/// Bannière compacte : fourchette de prix de la wishlist affichée.
class WishlistBudgetBanner extends StatelessWidget {
  final List<CollectionItem> items;

  const WishlistBudgetBanner({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final boardgames = items.where((i) => i.isWishlist).toList();
    if (boardgames.isEmpty) return const SizedBox.shrink();

    double usedMin = 0;
    double usedMax = 0;
    double newMin = 0;
    double newMax = 0;
    var usedCount = 0;
    var newCount = 0;

    for (final item in boardgames) {
      final used = marketSecondhandPriceFromMetadata(item.metadata);
      final neu = marketNewPriceMinFromMetadata(item.metadata);
      if (used != null && used > 0) {
        usedMin += used;
        usedMax += used;
        usedCount++;
      }
      if (neu != null && neu > 0) {
        newMin += neu;
        newMax += neu;
        newCount++;
      }
    }

    if (usedCount == 0 && newCount == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _label(usedMin, usedMax, usedCount, newMin, newMax, newCount),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Text(
              '${boardgames.length} jeux',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _label(
    double usedMin,
    double usedMax,
    int usedCount,
    double newMin,
    double newMax,
    int newCount,
  ) {
    final parts = <String>[];
    if (usedCount > 0) {
      parts.add(
        'Occ. ~${formatEuroChip(usedMin, compact: false)}'
        '${usedCount < items.length ? ' ($usedCount estimés)' : ''}',
      );
    }
    if (newCount > 0) {
      parts.add(
        'Neuf ~${formatEuroChip(newMin, compact: false)}'
        '${newCount < items.length ? ' ($newCount prix)' : ''}',
      );
    }
    return parts.join(' · ');
  }
}
