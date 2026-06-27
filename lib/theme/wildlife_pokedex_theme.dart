import 'package:flutter/material.dart';

import '../models/wildlife_taxonomy.dart';

/// Charte « console / Pokédex rétro V3 » — découplée du reste de l'app.
abstract final class WildlifePokedexTheme {
  static const bg = Color(0xFF050B14);
  static const panel = Color(0xFF0D1B2A);
  static const neon = Color(0xFF39FF14);
  static const neonDim = Color(0xFF1B5E20);
  static const accent = Color(0xFF00E5FF);
  static const warn = Color(0xFFFFD600);
  static const text = Color(0xFFE8F5E9);
  static const ink = Color(0xFF0A0A0A);

  /// Végétal = vert forêt, Champignons = violet, etc.
  static Color realmGlow(WildlifeRealm realm) => switch (realm) {
        WildlifeRealm.plantae => const Color(0xFF2E7D32),
        WildlifeRealm.fungi => const Color(0xFF7B1FA2),
        WildlifeRealm.animalia => const Color(0xFF8D6E63),
        WildlifeRealm.protista => const Color(0xFF26C6DA),
        WildlifeRealm.monera => const Color(0xFF5E35B1),
      };

  static Color kingdomGlow(WildlifeKingdom kingdom) => switch (kingdom) {
        WildlifeKingdom.fish => const Color(0xFF0277BD),
        WildlifeKingdom.insect => const Color(0xFFE65100),
        WildlifeKingdom.reptileAmphibian => const Color(0xFF558B2F),
        WildlifeKingdom.bird => const Color(0xFFBCAAA4),
        WildlifeKingdom.mammal => const Color(0xFF8D6E63),
        WildlifeKingdom.other => accent,
      };

  static List<BoxShadow> hardShadow({
    Color color = ink,
    Offset offset = const Offset(4, 4),
  }) =>
      [
        BoxShadow(
          color: color,
          offset: offset,
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ];

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
        border: Border.all(color: ink, width: 3),
        boxShadow: hardShadow(color: ink.withValues(alpha: 0.55)),
      );

  static BoxDecoration tileDecoration({Color? glow, double borderWidth = 3}) {
    final accentColor = glow ?? neon;
    return BoxDecoration(
      color: panel.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: ink, width: borderWidth),
      boxShadow: [
        ...hardShadow(),
        BoxShadow(
          color: accentColor.withValues(alpha: 0.35),
          offset: const Offset(0, 0),
          blurRadius: 10,
          spreadRadius: 0,
        ),
      ],
    );
  }

  static BoxDecoration retroPanel({Color? glow}) => BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ink, width: 3),
        boxShadow: hardShadow(),
      );

  static TextStyle titleStyle(BuildContext context) => const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.6,
        color: neon,
        shadows: [
          Shadow(color: Colors.black, offset: Offset(2, 2)),
          Shadow(color: Color(0x8839FF14), blurRadius: 8),
        ],
      );

  static TextStyle breadcrumbStyle() => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: text.withValues(alpha: 0.8),
        letterSpacing: 1,
      );

  static Widget thickProgress({
    required double value,
    required Color color,
    double height = 14,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: ink, width: 3),
        borderRadius: BorderRadius.circular(4),
        boxShadow: hardShadow(offset: const Offset(2, 2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            Container(height: height, color: panel),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(height: height, color: color),
            ),
          ],
        ),
      ),
    );
  }

  static Widget silhouetteOverlay({double questionSize = 36}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
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
              shadows: const [
                Shadow(color: Colors.black, offset: Offset(2, 2)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'NON OBSERVÉ',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              color: text.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  /// Bannière flash « CAPTURE RÉUSSIE ! »
  static Widget captureFlashBanner() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warn,
        border: Border.all(color: ink, width: 3),
        boxShadow: hardShadow(),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Text(
          'CAPTURE RÉUSSIE !',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            color: ink,
          ),
        ),
      ),
    );
  }
}
