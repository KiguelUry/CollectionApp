import '../models/boardgame_play_session.dart';

/// Noms distincts ayant déjà joué à ce jeu (historique local).
List<String> pastPlayerNamesFromSessions(List<BoardgamePlaySession> sessions) {
  final names = <String>{};
  for (final s in sessions) {
    if (s.players.isNotEmpty) {
      names.addAll(s.players.map((p) => p.trim()).where((p) => p.isNotEmpty));
    }
    final grid = s.scoreGrid;
    if (grid != null) {
      names.addAll(grid.activePlayers);
    }
  }
  final list = names.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}
