// Libellés joueurs / durée / notes pour les jeux de société.

int? parseBggBestPlayers(dynamic raw) {
  if (raw is int) return raw > 0 ? raw : null;
  if (raw is String) {
    final n = int.tryParse(raw.trim());
    return n != null && n > 0 ? n : null;
  }
  return null;
}

String? formatBggBestPlayersLabel(int? count) {
  if (count == null || count <= 0) return null;
  return 'Conseillé : $count';
}

/// Libellé compact pour la tuile (note /5, 1 décimale).
String? formatBggRatingChipLabel(dynamic raw) {
  final onFive = bggRatingOnFive(raw);
  if (onFive == null) return null;
  return onFive.toStringAsFixed(1);
}

/// Affichage Découvrir / listes : `★ 4.1` (toujours /5).
String formatBggRatingStarLabel(dynamic raw, {String placeholder = '…'}) {
  final label = formatBggRatingChipLabel(raw);
  if (label == null) return placeholder;
  return '★ $label';
}

/// Note moyenne BGG brute (échelle 0–10 côté API).
double? parseBggAvgRating(dynamic raw) {
  if (raw is num) return raw > 0 ? raw.toDouble() : null;
  if (raw is String) {
    final n = double.tryParse(raw.trim());
    return n != null && n > 0 ? n : null;
  }
  return null;
}

/// Note BGG brute /10 (1 décimale) — usage interne / conversions.
double? bggRatingOnTen(dynamic raw) {
  final avg = parseBggAvgRating(raw);
  if (avg == null) return null;
  return double.parse(avg.toStringAsFixed(1));
}

/// Note BGG affichée sur /5 (API /10 ÷ 2).
double? bggRatingOnFive(dynamic raw) {
  final onTen = bggRatingOnTen(raw);
  if (onTen == null) return null;
  return double.parse((onTen / 2).toStringAsFixed(1));
}

/// Normalise une note personnelle stockée vers /5 pour l’UI.
/// Anciennes notes /10 (`rating_scale=10` ou valeur > 5) → ÷2.
double? personalRatingOnFive(double? stored, {Map<String, dynamic>? metadata}) {
  if (stored == null || stored < 0) return null;
  final scale = metadata?['rating_scale']?.toString();
  if (scale == '10' || stored > 5.0) {
    return double.parse((stored / 2).clamp(0, 5).toStringAsFixed(1));
  }
  return double.parse(stored.clamp(0, 5).toStringAsFixed(1));
}

/// @Deprecated — utiliser [personalRatingOnFive].
double? personalRatingOnTen(double? stored, {Map<String, dynamic>? metadata}) {
  final onFive = personalRatingOnFive(stored, metadata: metadata);
  if (onFive == null) return null;
  return double.parse((onFive * 2).toStringAsFixed(1));
}

String? formatPersonalRatingLabel(
  double? stored, {
  Map<String, dynamic>? metadata,
}) {
  final onFive = personalRatingOnFive(stored, metadata: metadata);
  if (onFive == null) return null;
  return onFive.toStringAsFixed(1);
}

String? formatPlayerCount(int? min, int? max) {
  if (min == null && max == null) return null;

  if (min != null && max != null) {
    if (min == max) {
      return min == 1 ? '1 joueur' : '$min joueurs';
    }
    return '$min–$max joueurs';
  }

  final n = min ?? max!;
  return n == 1 ? '1 joueur' : '$n joueurs';
}

String? formatPlayingTime(int? minutes) {
  if (minutes == null || minutes <= 0) return null;
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '${h}h';
  return '${h}h${m.toString().padLeft(2, '0')}';
}
