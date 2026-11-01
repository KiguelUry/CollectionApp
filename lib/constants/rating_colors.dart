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

/// Spectre arc-en-ciel continu 0.0 → 5.0 (luminosité constante, zéro brun).
Color ratingColor(double rating) {
  final stepped = (rating.clamp(0.0, 5.0) * 2).round() / 2;
  return switch (stepped) {
    0.0 => const Color(0xFFEF4444), // Rouge franc
    0.5 => const Color(0xFFF95738), // Vermillon
    1.0 => const Color(0xFFF97316), // Orange pur
    1.5 => const Color(0xFFFB923C), // Orange mandarine
    2.0 => const Color(0xFFF59E0B), // Ambre doré
    2.5 => const Color(0xFFEAB308), // Jaune soleil
    3.0 => const Color(0xFF84CC16), // Vert citron
    3.5 => const Color(0xFF22C55E), // Vert pomme
    4.0 => const Color(0xFF10B981), // Vert émeraude
    4.5 => const Color(0xFF06B6D4), // Turquoise
    _ => const Color(0xFF38BDF8), // Bleu GOAT
  };
}

Color ratingBadgeStarColor(double rating) => ratingColor(rating);

Color ratingBadgeBorderColor(double rating) {
  final stepped = (rating.clamp(0.0, 5.0) * 2).round() / 2;
  if (stepped == 5.0) return const Color(0xFF7DD3FC);
  return ratingColor(stepped);
}

/// Préférence d'affichage de la puce note sur les tuiles.
enum TileRatingDisplayMode {
  personalThenCommunity,
  alwaysCommunity,
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

/// Préférence puce série : auto = globale > moyenne > communauté.
enum SeriesRatingDisplayPref {
  auto,
  global,
  average,
  community;

  static SeriesRatingDisplayPref fromMetadata(Map<String, dynamic>? meta) {
    final raw = meta?['preferred_rating_display']?.toString();
    return switch (raw) {
      'global' => SeriesRatingDisplayPref.global,
      'average' => SeriesRatingDisplayPref.average,
      'community' => SeriesRatingDisplayPref.community,
      _ => SeriesRatingDisplayPref.auto,
    };
  }

  String get dbValue => name;
}
