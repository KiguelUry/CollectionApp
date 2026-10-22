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

/// Libellé compact pour la tuile (note /10, 1 décimale).
String? formatBggRatingChipLabel(dynamic raw) {
  final onTen = bggRatingOnTen(raw);
  if (onTen == null) return null;
  return onTen.toStringAsFixed(1);
}

/// Affichage Découvrir / listes : `★ 8.3` (toujours /10).
String formatBggRatingStarLabel(dynamic raw, {String placeholder = '…'}) {
  final label = formatBggRatingChipLabel(raw);
  if (label == null) return placeholder;
  return '★ $label';
}

/// Note moyenne BGG brute (échelle 0–10).
double? parseBggAvgRating(dynamic raw) {
  if (raw is num) return raw > 0 ? raw.toDouble() : null;
  if (raw is String) {
    final n = double.tryParse(raw.trim());
    return n != null && n > 0 ? n : null;
  }
  return null;
}

/// Note BGG affichée sur /10 (1 décimale).
double? bggRatingOnTen(dynamic raw) {
  final avg = parseBggAvgRating(raw);
  if (avg == null) return null;
  // Si une ancienne conversion /5 a fuité en cache (< 5.05 et pas > 5),
  // on ne remultiplie pas : BGG API est déjà /10.
  return double.parse(avg.toStringAsFixed(1));
}

/// @Deprecated — alias de [bggRatingOnTen] (notes unifiées /10).
double? bggRatingOnFive(dynamic raw) => bggRatingOnTen(raw);

/// Normalise une note personnelle stockée vers /10.
/// Anciennes notes /5 (≤ 5.0 sans flag) → ×2.
double? personalRatingOnTen(double? stored, {Map<String, dynamic>? metadata}) {
  if (stored == null || stored <= 0) return null;
  final scale = metadata?['rating_scale']?.toString();
  if (scale == '10') {
    return double.parse(stored.clamp(0, 10).toStringAsFixed(1));
  }
  if (stored <= 5.0) {
    return double.parse((stored * 2).clamp(0, 10).toStringAsFixed(1));
  }
  return double.parse(stored.clamp(0, 10).toStringAsFixed(1));
}

String? formatPersonalRatingLabel(double? stored, {Map<String, dynamic>? metadata}) {
  final onTen = personalRatingOnTen(stored, metadata: metadata);
  if (onTen == null) return null;
  return onTen.toStringAsFixed(1);
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
