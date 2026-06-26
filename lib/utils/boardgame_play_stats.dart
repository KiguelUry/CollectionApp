import '../models/boardgame_play_session.dart';
import '../models/boardgame_score_grid.dart';

class BoardgameScoreHighlight {
  final String player;
  final int score;
  final DateTime date;
  final int sessionIndex;

  const BoardgameScoreHighlight({
    required this.player,
    required this.score,
    required this.date,
    required this.sessionIndex,
  });
}

class BoardgameWinHighlight {
  final String name;
  final int wins;
  final int gamesPlayed;

  const BoardgameWinHighlight({
    required this.name,
    required this.wins,
    this.gamesPlayed = 0,
  });
}

class BoardgameAverageHighlight {
  final String player;
  final double average;
  final int games;

  const BoardgameAverageHighlight({
    required this.player,
    required this.average,
    required this.games,
  });
}

class BoardgameDuoHighlight {
  final String playerA;
  final String playerB;
  final int winsTogether;

  const BoardgameDuoHighlight({
    required this.playerA,
    required this.playerB,
    required this.winsTogether,
  });

  String get label => '$playerA & $playerB';
}

/// Ligne matricielle : joueur + parties + valeurs étendues (scores, etc.).
class BoardgameMatrixRow {
  final String player;
  final int gamesPlayed;
  final List<int> values;
  final List<int> sessionIndices;

  const BoardgameMatrixRow({
    required this.player,
    required this.gamesPlayed,
    required this.values,
    required this.sessionIndices,
  });
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
    return BoardgameRankingStats.fromSessions(sessions).legacySummary;
  }
}

class BoardgameRankingStats {
  final List<BoardgameWinHighlight> winPodium;
  final List<BoardgameAverageHighlight> allAverages;
  final List<BoardgameScoreHighlight> allScores;
  final List<String> allPlayerNames;
  final List<BoardgameDuoHighlight> topDuos;
  final Map<String, int> gamesPlayedByPlayer;
  final Map<String, int> lastPlaceByPlayer;
  final List<BoardgameMatrixRow> scoreMatrixRows;
  final List<BoardgameMatrixRow> averageMatrixRows;
  final List<BoardgameMatrixRow> winsMatrixRows;

  const BoardgameRankingStats({
    required this.winPodium,
    required this.allAverages,
    required this.allScores,
    required this.allPlayerNames,
    required this.topDuos,
    required this.gamesPlayedByPlayer,
    required this.lastPlaceByPlayer,
    required this.scoreMatrixRows,
    required this.averageMatrixRows,
    required this.winsMatrixRows,
  });

  BoardgamePlayAggregateStats get legacySummary => BoardgamePlayAggregateStats(
        winPodium: winPodium,
        bestScores: allScores.take(5).toList(),
        worstScores: List<BoardgameScoreHighlight>.from(allScores)
          ..sort((a, b) => b.score.compareTo(a.score))
          ..take(5),
      );

  factory BoardgameRankingStats.fromSessions(
    List<BoardgamePlaySession> sessions,
  ) {
    final winCounts = <String, int>{};
    final lastCounts = <String, int>{};
    final gamesPlayed = <String, int>{};
    final scoreSums = <String, int>{};
    final scoreCounts = <String, int>{};
    final scoresByPlayer = <String, List<BoardgameScoreHighlight>>{};
    final allScores = <BoardgameScoreHighlight>[];
    final rawNames = <String>{};
    final duoCounts = <String, int>{};

    void bumpGames(Iterable<String> names) {
      for (final n in names) {
        final t = n.trim();
        if (t.isEmpty) continue;
        gamesPlayed[t] = (gamesPlayed[t] ?? 0) + 1;
        rawNames.add(t);
      }
    }

    void recordDuoWinners(List<String> winners) {
      final unique = winners.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      for (var i = 0; i < unique.length; i++) {
        for (var j = i + 1; j < unique.length; j++) {
          final key = _duoKey(unique[i], unique[j]);
          duoCounts[key] = (duoCounts[key] ?? 0) + 1;
        }
      }
    }

    for (var sessionIdx = 0; sessionIdx < sessions.length; sessionIdx++) {
      final session = sessions[sessionIdx];
      final participants = _sessionParticipants(session);
      bumpGames(participants);

      if (session.winCondition == BoardgameWinCondition.cooperative) {
        if (session.coopVictory == true && participants.isNotEmpty) {
          for (final p in participants) {
            winCounts[p] = (winCounts[p] ?? 0) + 1;
          }
          recordDuoWinners(participants);
        }
        continue;
      }

      final winners = _winningPlayers(session);
      for (final w in winners) {
        winCounts[w] = (winCounts[w] ?? 0) + 1;
      }
      if (winners.isNotEmpty) recordDuoWinners(winners);

      final losers = _losingPlayers(session);
      for (final l in losers) {
        lastCounts[l] = (lastCounts[l] ?? 0) + 1;
      }

      final grid = session.scoreGrid;
      if (session.trackScores && grid != null && grid.hasScores) {
        final totals = grid.columnTotals();
        for (var i = 0; i < grid.players.length; i++) {
          final name = grid.players[i].trim();
          if (name.isEmpty || !grid.columnHasScores(i)) continue;
          rawNames.add(name);
          final score = i < totals.length ? totals[i] : 0;
          scoreSums[name] = (scoreSums[name] ?? 0) + score;
          scoreCounts[name] = (scoreCounts[name] ?? 0) + 1;
          final entry = BoardgameScoreHighlight(
            player: name,
            score: score,
            date: session.date,
            sessionIndex: sessionIdx,
          );
          allScores.add(entry);
          scoresByPlayer.putIfAbsent(name, () => []).add(entry);
        }
      }
    }

    final podium = winCounts.entries
        .map(
          (e) => BoardgameWinHighlight(
            name: e.key,
            wins: e.value,
            gamesPlayed: gamesPlayed[e.key] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => b.wins.compareTo(a.wins));

    final averages = scoreCounts.entries
        .map(
          (e) => BoardgameAverageHighlight(
            player: e.key,
            average: scoreSums[e.key]! / e.value,
            games: e.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.average.compareTo(a.average));

    allScores.sort((a, b) => b.score.compareTo(a.score));

    final duos = duoCounts.entries
        .map((e) {
          final parts = e.key.split('\u0000');
          return BoardgameDuoHighlight(
            playerA: parts[0],
            playerB: parts[1],
            winsTogether: e.value,
          );
        })
        .toList()
      ..sort((a, b) => b.winsTogether.compareTo(a.winsTogether));

    final scoreMatrix = _buildScoreMatrix(scoresByPlayer, gamesPlayed);
    final averageMatrix = _buildAverageMatrix(averages, gamesPlayed);
    final winsMatrix = _buildWinsMatrix(podium, lastCounts, gamesPlayed);

    return BoardgameRankingStats(
      winPodium: podium,
      allAverages: averages,
      allScores: allScores,
      allPlayerNames: rawNames.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      topDuos: duos.take(5).toList(),
      gamesPlayedByPlayer: gamesPlayed,
      lastPlaceByPlayer: lastCounts,
      scoreMatrixRows: scoreMatrix,
      averageMatrixRows: averageMatrix,
      winsMatrixRows: winsMatrix,
    );
  }

  static String _duoKey(String a, String b) {
    final x = a.toLowerCase();
    final y = b.toLowerCase();
    return x.compareTo(y) <= 0 ? '$a\u0000$b' : '$b\u0000$a';
  }

  static List<String> _sessionParticipants(BoardgamePlaySession session) {
    if (session.players.isNotEmpty) {
      return session.players.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    }
    return session.scoreGrid?.activePlayers ?? [];
  }

  static List<String> _winningPlayers(BoardgamePlaySession session) {
    final grid = session.scoreGrid;
    final winner = session.effectiveWinner?.trim();
    if (winner == null || winner.isEmpty) return [];

    if (session.useTeams && grid != null && grid.hasTeams) {
      final out = <String>[];
      for (var i = 0; i < grid.players.length; i++) {
        if (grid.teams[i]?.trim() == winner) {
          final n = grid.players[i].trim();
          if (n.isNotEmpty) out.add(n);
        }
      }
      if (out.isNotEmpty) return out;
    }
    return [winner];
  }

  static List<String> _losingPlayers(BoardgamePlaySession session) {
    if (session.winCondition == BoardgameWinCondition.cooperative) return [];
    final grid = session.scoreGrid;
    if (grid == null || !grid.hasScores) return [];

    final winners = grid.winningColumnIndices(session.winCondition);
    if (winners.isEmpty) return [];

    final losers = <String>[];
    for (var i = 0; i < grid.players.length; i++) {
      final name = grid.players[i].trim();
      if (name.isEmpty || !grid.columnHasScores(i)) continue;
      if (!winners.contains(i)) losers.add(name);
    }
    return losers;
  }

  static List<BoardgameMatrixRow> _buildScoreMatrix(
    Map<String, List<BoardgameScoreHighlight>> byPlayer,
    Map<String, int> gamesPlayed,
  ) {
    final rows = <BoardgameMatrixRow>[];
    for (final e in byPlayer.entries) {
      final sorted = List<BoardgameScoreHighlight>.from(e.value)
        ..sort((a, b) => b.score.compareTo(a.score));
      rows.add(
        BoardgameMatrixRow(
          player: e.key,
          gamesPlayed: gamesPlayed[e.key] ?? sorted.length,
          values: sorted.map((s) => s.score).toList(),
          sessionIndices: sorted.map((s) => s.sessionIndex).toList(),
        ),
      );
    }
    rows.sort((a, b) {
      final av = a.values.isEmpty ? -1 << 30 : a.values.first;
      final bv = b.values.isEmpty ? -1 << 30 : b.values.first;
      return bv.compareTo(av);
    });
    return rows;
  }

  static List<BoardgameMatrixRow> _buildAverageMatrix(
    List<BoardgameAverageHighlight> averages,
    Map<String, int> gamesPlayed,
  ) {
    return averages
        .map(
          (a) => BoardgameMatrixRow(
            player: a.player,
            gamesPlayed: gamesPlayed[a.player] ?? a.games,
            values: [a.average.round()],
            sessionIndices: const [],
          ),
        )
        .toList();
  }

  static List<BoardgameMatrixRow> _buildWinsMatrix(
    List<BoardgameWinHighlight> podium,
    Map<String, int> lastCounts,
    Map<String, int> gamesPlayed,
  ) {
    final all = <String>{
      ...podium.map((e) => e.name),
      ...lastCounts.keys,
      ...gamesPlayed.keys,
    };
    final rows = all
        .map(
          (name) => BoardgameMatrixRow(
            player: name,
            gamesPlayed: gamesPlayed[name] ?? 0,
            values: [
              podium.firstWhere((p) => p.name == name, orElse: () => BoardgameWinHighlight(name: name, wins: 0)).wins,
            ],
            sessionIndices: const [],
          ),
        )
        .toList()
      ..sort((a, b) => b.values.first.compareTo(a.values.first));
    return rows;
  }
}
