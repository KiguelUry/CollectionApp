import 'package:flutter/material.dart';
import '../models/collection_summary.dart';
import 'collection_summary_card.dart';

/// Vue d'ensemble repliable pour l'écran Collections.
class CollapsibleCollectionOverview extends StatefulWidget {
  final CollectionSummary summary;
  final VoidCallback? onWishlistTap;
  final VoidCallback? onStatsTap;

  const CollapsibleCollectionOverview({
    super.key,
    required this.summary,
    this.onWishlistTap,
    this.onStatsTap,
  });

  @override
  State<CollapsibleCollectionOverview> createState() =>
      _CollapsibleCollectionOverviewState();
}

class _CollapsibleCollectionOverviewState
    extends State<CollapsibleCollectionOverview> {
  bool _expanded = false;

  String _compactLine(CollectionSummary s) {
    final parts = <String>[
      '${s.ownedCount} objet${s.ownedCount > 1 ? 's' : ''}',
      if (s.wishlistCount > 0) '♥ ${s.wishlistCount} wishlist',
    ];
    if (s.hasAnyValue) {
      parts.add('${s.totalPurchaseValue.toStringAsFixed(0)} €');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.insights, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Vue d\'ensemble',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _expanded ? 'Détails' : _compactLine(widget.summary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: CollectionSummaryCard(
                summary: widget.summary,
                onWishlistTap: widget.onWishlistTap,
                onStatsTap: widget.onStatsTap,
                showHeader: false,
              ),
            ),
        ],
      ),
    );
  }
}
