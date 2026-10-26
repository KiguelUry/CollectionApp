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
