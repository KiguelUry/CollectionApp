import 'package:flutter/material.dart';

/// Charte « console / Pokédex » — découplée du reste de l'app.
abstract final class WildlifePokedexTheme {
  static const bg = Color(0xFF050B14);
  static const panel = Color(0xFF0D1B2A);
  static const neon = Color(0xFF39FF14);
  static const neonDim = Color(0xFF1B5E20);
  static const accent = Color(0xFF00E5FF);
  static const warn = Color(0xFFFFD600);
  static const text = Color(0xFFE8F5E9);

  static BoxDecoration screenDecoration() => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF020810), Color(0xFF0A1628), Color(0xFF051018)],
        ),
      );

  static BoxDecoration tileDecoration({Color? glow}) => BoxDecoration(
        color: panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (glow ?? neon).withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (glow ?? neon).withValues(alpha: 0.18),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      );

  static TextStyle titleStyle(BuildContext context) => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: neon,
        shadows: [
          Shadow(color: neon.withValues(alpha: 0.5), blurRadius: 8),
        ],
      );

  static TextStyle breadcrumbStyle() => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: text.withValues(alpha: 0.75),
        letterSpacing: 0.6,
      );
}
