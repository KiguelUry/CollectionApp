import 'package:flutter/material.dart';

import '../constants/rating_colors.dart';
import '../services/settings_service.dart';

/// Résultat d'affichage pour une puce ★ sur tuile.
class TileRatingChip {
  final String label;
  final Color color;
  final bool isPersonal;

  const TileRatingChip({
    required this.label,
    required this.color,
    required this.isPersonal,
  });

  static const empty = TileRatingChip(
    label: '★ —',
    color: RatingColors.community,
    isPersonal: false,
  );
}

/// Choisit perso / communauté selon [TileRatingDisplayMode].
TileRatingChip resolveTileRating({
  double? personalOnFive,
  double? communityOnFive,
  TileRatingDisplayMode? mode,
}) {
  final m = mode ?? SettingsService.instance.tileRatingDisplayMode;
  final perso = (personalOnFive != null && personalOnFive > 0)
      ? personalOnFive
      : null;
  final commu = (communityOnFive != null && communityOnFive > 0)
      ? communityOnFive
      : null;

  switch (m) {
    case TileRatingDisplayMode.alwaysCommunity:
      if (commu == null) return TileRatingChip.empty;
      return TileRatingChip(
        label: '★ ${commu.toStringAsFixed(1)}',
        color: RatingColors.community,
        isPersonal: false,
      );
    case TileRatingDisplayMode.onlyPersonal:
      if (perso == null) return TileRatingChip.empty;
      return TileRatingChip(
        label: '★ ${perso.toStringAsFixed(1)}',
        color: RatingColors.personal,
        isPersonal: true,
      );
    case TileRatingDisplayMode.personalThenCommunity:
      if (perso != null) {
        return TileRatingChip(
          label: '★ ${perso.toStringAsFixed(1)}',
          color: RatingColors.personal,
          isPersonal: true,
        );
      }
      if (commu != null) {
        return TileRatingChip(
          label: '★ ${commu.toStringAsFixed(1)}',
          color: RatingColors.community,
          isPersonal: false,
        );
      }
      return TileRatingChip.empty;
  }
}
