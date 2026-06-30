// Libellés joueurs / durée pour les jeux de société.

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

/// Libellé compact pour la tuile collection (note /5).
String? formatBggRatingChipLabel(dynamic raw) {
  final onFive = bggRatingOnFive(raw);
  if (onFive == null) return null;
  return onFive.toStringAsFixed(1);
}

/// Note moyenne BGG (échelle 0–10).
double? parseBggAvgRating(dynamic raw) {
  if (raw is num) return raw > 0 ? raw.toDouble() : null;
  if (raw is String) {
    final n = double.tryParse(raw.trim());
    return n != null && n > 0 ? n : null;
  }
  return null;
}

/// Convertit la note BGG (/10) en étoiles sur 5.
double? bggRatingOnFive(dynamic raw) {
  final avg = parseBggAvgRating(raw);
  if (avg == null) return null;
  return avg / 2.0;
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
