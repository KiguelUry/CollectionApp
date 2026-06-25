import 'package:flutter/material.dart';

import '../../models/collection_item.dart';
import '../../models/wildlife_taxonomy.dart';
import '../../theme/wildlife_pokedex_theme.dart';

/// Statistiques terrain (sans % global trompeur).
class PokedexStats {
  final int totalObservations;
  final int speciesWithObservations;
  final int speciesInDex;
  final String? topFamilyLabel;
  final int topFamilyObservations;

  const PokedexStats({
    required this.totalObservations,
    required this.speciesWithObservations,
    required this.speciesInDex,
    this.topFamilyLabel,
    this.topFamilyObservations = 0,
  });

  factory PokedexStats.fromItems(List<CollectionItem> items) {
    var obs = 0;
    var withObs = 0;
    final familyObs = <String, int>{};

    for (final item in items) {
      final count = item.gamesPlayed ?? 0;
      if (count > 0) {
        withObs++;
        obs += count;
        final kingdom = WildlifeKingdom.fromDb(
          item.metadata?['wildlife_kingdom'] as String?,
        );
        final familyId =
            item.metadata?['wildlife_family'] as String? ?? 'other';
        final label = kingdom != null
            ? WildlifeTaxonomy.familyLabel(familyId, kingdom) ?? familyId
            : familyId;
        familyObs[label] = (familyObs[label] ?? 0) + count;
      }
    }

    String? topFamily;
    var topCount = 0;
    familyObs.forEach((label, c) {
      if (c > topCount) {
        topCount = c;
        topFamily = label;
      }
    });

    return PokedexStats(
      totalObservations: obs,
      speciesWithObservations: withObs,
      speciesInDex: items.length,
      topFamilyLabel: topFamily,
      topFamilyObservations: topCount,
    );
  }
}

class PokedexStatsPanel extends StatelessWidget {
  final PokedexStats stats;

  const PokedexStatsPanel({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: WildlifePokedexTheme.tileDecoration(
        glow: WildlifePokedexTheme.accent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _statChip(
                '${stats.totalObservations}',
                'observations',
                WildlifePokedexTheme.neon,
              ),
              const SizedBox(width: 10),
              _statChip(
                '${stats.speciesWithObservations}',
                'espèces vues',
                WildlifePokedexTheme.accent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${stats.speciesInDex} fiche${stats.speciesInDex > 1 ? 's' : ''} au carnet',
            style: TextStyle(
              fontSize: 11,
              color: WildlifePokedexTheme.text.withValues(alpha: 0.65),
            ),
          ),
          if (stats.topFamilyLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              'Famille la plus observée',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: WildlifePokedexTheme.text.withValues(alpha: 0.5),
                letterSpacing: 0.8,
              ),
            ),
            Text(
              '${stats.topFamilyLabel} (${stats.topFamilyObservations} obs.)',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: WildlifePokedexTheme.warn,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: WildlifePokedexTheme.text.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
