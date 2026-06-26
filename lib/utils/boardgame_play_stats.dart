import '../models/boardgame_play_session.dart';

class BoardgameScoreHighlight {
  final String player;
  final int score;
  final DateTime date;

  const BoardgameScoreHighlight({
    required this.player,
    required this.score,
    required this.date,
  });
}

class BoardgameWinHighlight {
  final String name;
  final int wins;

  const BoardgameWinHighlight({required this.name, required this.wins});
}

class BoardgamePlayAggregateStats {
  final List<BoardgameWinHighlight> winPodium;
  final List<BoardgameScoreHighlight> bestScores;
  final List<BoardgameScoreHighlight> worstScores;

  const BoardgamePlayAggregateStats({
    required this.winPodium,
    required this.bestScores,
    required this.worstScores,
  });

  factory BoardgamePlayAggregateStats.fromSessions(
    List<BoardgamePlaySession> sessions,
  ) {
    final winCounts = <String, int>{};
    final scores = <BoardgameScoreHighlight>[];

    for (final session in sessions) {
      final winner = session.effectiveWinner;
      if (winner != null && winner.trim().isNotEmpty) {
        winCounts[winner.trim()] = (winCounts[winner.trim()] ?? 0) + 1;
      }

      final grid = session.scoreGrid;
      if (session.trackScores && grid != null && grid.hasScores) {
        final totals = grid.columnTotals();
        for (var i = 0; i < grid.players.length; i++) {
          final name = grid.players[i].trim();
          if (name.isEmpty) continue;
          if (i >= totals.length) continue;
          scores.add(
            BoardgameScoreHighlight(
              player: name,
              score: totals[i],
              date: session.date,
            ),
          );
        }
      }
    }

    final podium = winCounts.entries
        .map((e) => BoardgameWinHighlight(name: e.key, wins: e.value))
        .toList()
      ..sort((a, b) => b.wins.compareTo(a.wins));

    scores.sort((a, b) => b.score.compareTo(a.score));
    final best = scores.take(5).toList();
    final worst = scores.isEmpty
        ? <BoardgameScoreHighlight>[]
        : (List<BoardgameScoreHighlight>.from(scores)
          ..sort((a, b) => a.score.compareTo(b.score)))
            .take(5)
            .toList();

    return BoardgamePlayAggregateStats(
      winPodium: podium.take(5).toList(),
      bestScores: best,
      worstScores: worst,
    );
  }
}
