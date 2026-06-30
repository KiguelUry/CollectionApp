import 'package:flutter/material.dart';

import '../models/collection_insight.dart';
import '../screens/loans_screen.dart';
import '../screens/tech_collection_screen.dart';
import '../screens/tcg/tcg_completion_screen.dart';

/// Rappels automatiques sur le hub principal (garanties, prêts, TCG…).
class CollectionInsightsBanner extends StatelessWidget {
  final List<CollectionInsight> items;

  const CollectionInsightsBanner({super.key, required this.items});

  void _openInsight(BuildContext context, CollectionInsight insight) {
    final route = switch (insight.kind) {
      CollectionInsightKind.warranty => const TechCollectionScreen(),
      CollectionInsightKind.loan => const LoansScreen(),
      CollectionInsightKind.tcg => const TcgCompletionScreen(),
      CollectionInsightKind.books => null,
    };
    if (route == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => route),
    );
  }

  IconData _icon(CollectionInsightKind kind) => switch (kind) {
        CollectionInsightKind.warranty => Icons.verified_outlined,
        CollectionInsightKind.loan => Icons.swap_horiz_rounded,
        CollectionInsightKind.tcg => Icons.style_outlined,
        CollectionInsightKind.books => Icons.menu_book_outlined,
      };

  Color _accent(CollectionInsightKind kind, ColorScheme scheme) =>
      switch (kind) {
        CollectionInsightKind.warranty => const Color(0xFF3949AB),
        CollectionInsightKind.loan => Colors.deepOrange,
        CollectionInsightKind.tcg => const Color(0xFFE65100),
        CollectionInsightKind.books => scheme.primary,
      };

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rappels',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Garanties high-tech, prêts de +30 jours, cartes à compléter…',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message:
                    'Alertes calculées depuis ta collection. Appuie sur une ligne pour ouvrir la section concernée.',
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        for (final insight in items)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            color: _accent(insight.kind, scheme).withValues(alpha: 0.08),
            child: ListTile(
              dense: true,
              leading: Icon(
                _icon(insight.kind),
                color: _accent(insight.kind, scheme),
              ),
              title: Text(
                insight.message,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              trailing: insight.actionLabel != null
                  ? Text(
                      insight.actionLabel!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accent(insight.kind, scheme),
                      ),
                    )
                  : null,
              onTap: () => _openInsight(context, insight),
            ),
          ),
      ],
    );
  }
}
