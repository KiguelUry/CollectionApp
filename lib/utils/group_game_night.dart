import '../models/collection_item.dart';

/// Jeu proposé pour une soirée (tirage groupe).
class GameNightPick {
  final CollectionItem item;
  final int score;

  const GameNightPick(this.item, this.score);
}

int? _playerCount(CollectionItem item) {
  final max = item.maxPlayers;
  if (max != null && max > 0) return max;
  return item.minPlayers;
}

bool _fitsPlayerCount(CollectionItem item, int players) {
  final min = item.minPlayers ?? 1;
  final max = item.maxPlayers ?? 99;
  if (players < min) return false;
  if (max > 0 && players > max) return false;
  return true;
}

/// Tire [count] jeux de société adaptés au nombre de joueurs du groupe.
/// Priorise les jeux jamais joués récemment (peu de parties en metadata).
List<GameNightPick> pickGamesForGameNight(
  Iterable<CollectionItem> boardgames, {
  required int playerCount,
  int count = 3,
}) {
  if (playerCount < 1) playerCount = 1;
  final candidates = boardgames
      .where((i) => !i.isWishlist && !i.isExpansion && !i.isSold)
      .where((i) => _fitsPlayerCount(i, playerCount))
      .toList();
  if (candidates.isEmpty) return [];

  final scored = <GameNightPick>[];
  for (final item in candidates) {
    var score = 100;
    final plays = item.gamesPlayed ?? item.metadata?['games_played'] as int? ?? 0;
    score -= (plays * 8).clamp(0, 80);
    final maxP = _playerCount(item);
    if (maxP != null && maxP == playerCount) score += 25;
    if (item.minPlayers != null && item.minPlayers == playerCount) score += 15;
    if (item.playingTime != null) {
      if (item.playingTime! <= 45) score += 10;
      if (item.playingTime! >= 120) score -= 5;
    }
    final rating = item.rating ?? item.metadata?['bgg_avg_rating'];
    if (rating is num && rating >= 7.5) score += 12;
    scored.add(GameNightPick(item, score));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));

  final picks = <GameNightPick>[];
  final seen = <String>{};
  for (final p in scored) {
    if (picks.length >= count) break;
    if (seen.add(p.item.id)) picks.add(p);
  }
  return picks;
}

String formatGameNightShareText({
  required String groupName,
  required int playerCount,
  required List<GameNightPick> picks,
  String? inviteLink,
}) {
  final buf = StringBuffer('🎲 On joue à quoi ce soir ? — $groupName\n');
  buf.writeln('$playerCount joueur${playerCount > 1 ? 's' : ''} · 3 idées :\n');
  for (var i = 0; i < picks.length; i++) {
    final item = picks[i].item;
    final players = [
      if (item.minPlayers != null) item.minPlayers,
      if (item.maxPlayers != null) item.maxPlayers,
    ].whereType<int>().toList();
    final range = players.isEmpty
        ? ''
        : ' (${players.first}${players.length > 1 && players.last != players.first ? '–${players.last}' : ''} j.)';
    final time = item.playingTime != null && item.playingTime! > 0
        ? ' · ${item.playingTime} min'
        : '';
    buf.writeln('${i + 1}. ${item.title}$range$time');
  }
  if (inviteLink != null && inviteLink.isNotEmpty) {
    buf.writeln('\nRejoins-nous : $inviteLink');
  }
  buf.writeln('\n— via Collectingo');
  return buf.toString().trim();
}
