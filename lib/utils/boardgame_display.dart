/// Libellés joueurs / durée pour les jeux de société.
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
