import 'package:flutter/material.dart';

import '../../theme/wildlife_pokedex_theme.dart';

/// Jauge circulaire de complétion globale (style Pokédex).
class PokedexCompletionRing extends StatelessWidget {
  final double progress;
  final int speciesCount;
  final int observedCount;

  const PokedexCompletionRing({
    super.key,
    required this.progress,
    required this.speciesCount,
    required this.observedCount,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round();
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: CircularProgressIndicator(
              value: progress.clamp(0, 1),
              strokeWidth: 10,
              backgroundColor: WildlifePokedexTheme.panel,
              color: WildlifePokedexTheme.neon,
            ),
          ),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: WildlifePokedexTheme.panel.withValues(alpha: 0.95),
              border: Border.all(
                color: WildlifePokedexTheme.neon.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: WildlifePokedexTheme.neon.withValues(alpha: 0.25),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$pct%',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: WildlifePokedexTheme.neon,
                  ),
                ),
                Text(
                  '$observedCount/$speciesCount',
                  style: TextStyle(
                    fontSize: 11,
                    color: WildlifePokedexTheme.text.withValues(alpha: 0.7),
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
