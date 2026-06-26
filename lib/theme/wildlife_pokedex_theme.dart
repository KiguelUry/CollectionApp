import 'package:flutter/material.dart';

import '../models/wildlife_taxonomy.dart';

/// Charte « console / Pokédex rétro » — découplée du reste de l'app.
abstract final class WildlifePokedexTheme {
  static const bg = Color(0xFF050B14);
  static const panel = Color(0xFF0D1B2A);
  static const neon = Color(0xFF39FF14);
  static const neonDim = Color(0xFF1B5E20);
  static const accent = Color(0xFF00E5FF);
  static const warn = Color(0xFFFFD600);
  static const text = Color(0xFFE8F5E9);

  static Color realmGlow(WildlifeRealm realm) => switch (realm) {
        WildlifeRealm.plantae => const Color(0xFF1B5E20),
        WildlifeRealm.fungi => const Color(0xFFAB47BC),
        WildlifeRealm.animalia => neon,
        WildlifeRealm.protista => const Color(0xFF26C6DA),
        WildlifeRealm.monera => const Color(0xFF7E57C2),
      };

  static Color kingdomGlow(WildlifeKingdom kingdom) => switch (kingdom) {
        WildlifeKingdom.fish => const Color(0xFF0288D1),
        WildlifeKingdom.insect => const Color(0xFFE65100),
        WildlifeKingdom.reptileAmphibian => const Color(0xFF558B2F),
        WildlifeKingdom.bird => const Color(0xFF00ACC1),
        WildlifeKingdom.mammal => neon,
        WildlifeKingdom.other => accent,
      };

  static BoxDecoration screenDecoration() => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bg,
            panel.withValues(alpha: 0.95),
            const Color(0xFF051018),
          ],
        ),
        border: Border.all(color: neon.withValues(alpha: 0.25), width: 2),
      );

  static BoxDecoration tileDecoration({Color? glow, double borderWidth = 3}) =>
      BoxDecoration(
        color: panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (glow ?? neon).withValues(alpha: 0.75),
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: (glow ?? neon).withValues(alpha: 0.22),
            blurRadius: 14,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
      );

  static BoxDecoration retroPanel({Color? glow}) => BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (glow ?? neon), width: 3),
      );

  static TextStyle titleStyle(BuildContext context) => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        color: neon,
        shadows: [
          Shadow(color: neon.withValues(alpha: 0.55), blurRadius: 10),
          const Shadow(color: Colors.black54, offset: Offset(1, 1)),
        ],
      );

  static TextStyle breadcrumbStyle() => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: text.withValues(alpha: 0.75),
        letterSpacing: 0.8,
      );

  static Widget thickProgress({
    required double value,
    required Color color,
    double height = 14,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: [
          Container(
            height: height,
            color: panel,
          ),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: height,
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.8), width: 2),
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ],
      ),
    );
  }

  static Widget silhouetteOverlay({double questionSize = 36}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.88),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '?',
            style: TextStyle(
              fontSize: questionSize,
              fontWeight: FontWeight.w900,
              color: warn,
              shadows: [
                Shadow(color: warn.withValues(alpha: 0.8), blurRadius: 12),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'NON OBSERVÉ',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: text.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
