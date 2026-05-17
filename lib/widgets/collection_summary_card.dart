import 'package:flutter/material.dart';
import '../models/collection_summary.dart';

class CollectionSummaryCard extends StatelessWidget {
  final CollectionSummary summary;
  final VoidCallback? onWishlistTap;
  final VoidCallback? onStatsTap;

  const CollectionSummaryCard({
    super.key,
    required this.summary,
    this.onWishlistTap,
    this.onStatsTap,
  });

  String _formatMoney(double value) {
    if (value >= 1000) {
      return '${value.toStringAsFixed(0).replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]} ',
          )} €';
    }
    return '${value.toStringAsFixed(2)} €';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Vue d\'ensemble',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (onStatsTap != null)
                  TextButton.icon(
                    onPressed: onStatsTap,
                    icon: const Icon(Icons.bar_chart, size: 18),
                    label: const Text('Stats'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Objets possédés',
                    value: '${summary.ownedCount}',
                    icon: Icons.inventory_2_outlined,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: onWishlistTap,
                    borderRadius: BorderRadius.circular(12),
                    child: _StatTile(
                      label: 'Wishlist',
                      value: '${summary.wishlistCount}',
                      icon: Icons.favorite_border,
                      color: Colors.amber.shade800,
                      showChevron: onWishlistTap != null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Material(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onStatsTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary.hasAnyValue
                                  ? _formatMoney(summary.totalPurchaseValue)
                                  : '—',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              summary.hasAnyValue
                                  ? 'Valeur indicative · ${summary.pricedItemCount} prix renseigné${summary.pricedItemCount > 1 ? 's' : ''}'
                                  : 'Ajoute des prix d\'achat pour estimer',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onPrimaryContainer
                                    .withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onStatsTap != null)
                        Icon(Icons.chevron_right, color: scheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool showChevron;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              if (showChevron) ...[
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
