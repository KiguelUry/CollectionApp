import 'package:flutter/material.dart';

import '../utils/stats_dashboard.dart';

/// « 3,50 € / partie » sur la fiche d'un jeu possédé (rien si non calculable).
class CostPerPlayBadge extends StatelessWidget {
  final double? purchasePrice;
  final double? estimatedValue;
  final int plays;

  const CostPerPlayBadge({
    super.key,
    required this.purchasePrice,
    required this.estimatedValue,
    required this.plays,
  });

  @override
  Widget build(BuildContext context) {
    final cost = costPerPlay(
      purchasePrice: purchasePrice,
      estimatedValue: estimatedValue,
      plays: plays,
    );
    if (cost == null) return const SizedBox.shrink();
    final fromPurchase = purchasePrice != null && purchasePrice! > 0;
    final scheme = Theme.of(context).colorScheme;
    final accent = Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.savings_outlined, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatCostPerPlay(cost),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: accent,
                  ),
                ),
                Text(
                  '${fromPurchase ? 'Prix d\'achat' : 'Valeur estimée'} ÷ '
                  '$plays partie${plays > 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
