/// Libellés joueurs / durée pour les jeux de société.

/// Extrait 1–2 phrases (~240 car.) pour l’accroche BGG, pas le texte complet.
String? bggShortDescription(String? full) {
  if (full == null || full.trim().isEmpty) return null;
  final text = full.trim().replaceAll(RegExp(r'\s+'), ' ');

  final sentenceRe = RegExp(r'(?<=[.!?])\s+(?=[A-ZÀ-ÖØ-Þ«"(\[]|\d)');
  final parts = text.split(sentenceRe);

  final buffer = StringBuffer();
  for (var i = 0; i < parts.length && i < 2; i++) {
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(parts[i].trim());
    if (buffer.length >= 160) break;
  }

  var result = buffer.toString().trim();
  if (result.isEmpty) {
    result = text.length > 220 ? '${text.substring(0, 217).trimRight()}…' : text;
  } else if (result.length > 280) {
    result = '${result.substring(0, 277).trimRight()}…';
  }
  return result;
}

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
