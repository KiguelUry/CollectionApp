import 'package:flutter/material.dart';

/// Couleurs notes : communauté (or) vs personnelle (bleu métallique).
abstract final class RatingColors {
  /// Note communauté (BGG, AniList, Google Books…).
  static const Color community = Color(0xFFF59E0B);
  static const Color communityDark = Color(0xFFD97706);

  /// Ma note personnelle.
  static const Color personal = Color(0xFF38BDF8);
  static const Color personalBright = Color(0xFF60A5FA);
  static const Color personalDark = Color(0xFF0284C7);
}

/// Dégradé personnel 0.0 → 5.0, pas de 0.5 (11 paliers).
Color ratingColor(double rating) {
  final stepped = (rating.clamp(0.0, 5.0) * 2).round() / 2;
  return switch (stepped) {
    0.0 => const Color(0xFF991B1B),
    0.5 => const Color(0xFFEF4444),
    1.0 => const Color(0xFFF97316),
    1.5 => const Color(0xFFFB923C),
    2.0 => const Color(0xFFF59E0B),
    2.5 => const Color(0xFFEAB308),
    3.0 => const Color(0xFF84CC16),
    3.5 => const Color(0xFF14B8A6),
    4.0 => const Color(0xFF06B6D4),
    4.5 => const Color(0xFF3B82F6),
    _ => const Color(0xFF38BDF8),
  };
}

/// Préférence d'affichage de la puce note sur les tuiles.
enum TileRatingDisplayMode {
  /// Ma note perso si présente, sinon communauté.
  personalThenCommunity,

  /// Toujours la note communauté.
  alwaysCommunity,

  /// Uniquement ma note perso (ou —).
  onlyPersonal,
}

extension TileRatingDisplayModeX on TileRatingDisplayMode {
  String get label => switch (this) {
        TileRatingDisplayMode.personalThenCommunity =>
          'Perso puis communauté',
        TileRatingDisplayMode.alwaysCommunity => 'Toujours communauté',
        TileRatingDisplayMode.onlyPersonal => 'Uniquement ma note',
      };

  String get subtitle => switch (this) {
        TileRatingDisplayMode.personalThenCommunity =>
          'Bleu métallique si noté, sinon ★ or communauté',
        TileRatingDisplayMode.alwaysCommunity =>
          'Toujours ★ or (BGG / AniList / Google)',
        TileRatingDisplayMode.onlyPersonal =>
          'Bleu métallique uniquement, sinon —',
      };
}
