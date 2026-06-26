import 'package:intl/intl.dart';

import 'boardgame_score_grid.dart';

class BoardgamePlaySession {
  final DateTime date;
  final List<String> players;
  final String? winner;
  final Map<String, int>? scores;
  final BoardgameScoreGrid? scoreGrid;
  final String? notes;
  final bool trackScores;
  final BoardgameWinCondition winCondition;
  final bool useTeams;

  const BoardgamePlaySession({
    required this.date,
    required this.players,
    this.winner,
    this.scores,
    this.scoreGrid,
    this.notes,
    this.trackScores = false,
    this.winCondition = BoardgameWinCondition.highest,
    this.useTeams = false,
  });

  factory BoardgamePlaySession.fromJson(Map<String, dynamic> json) {
    final players = (json['players'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        [];
    BoardgameScoreGrid? grid;
    if (json['score_grid'] is Map) {
      grid = BoardgameScoreGrid.fromJson(
        Map<String, dynamic>.from(json['score_grid'] as Map),
      );
    }
    Map<String, int>? scores;
    final rawScores = json['scores'];
    if (rawScores is Map) {
      scores = rawScores.map(
        (k, v) => MapEntry(k.toString(), (v as num).round()),
      );
    }
    scores ??= grid?.hasScores == true ? grid!.toLegacyScores() : null;

    return BoardgamePlaySession(
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      players: grid?.activePlayers.isNotEmpty == true
          ? grid!.activePlayers
          : players,
      winner: json['winner']?.toString(),
      scores: scores,
      scoreGrid: grid,
      notes: json['notes']?.toString(),
      trackScores: json['track_scores'] as bool? ?? grid != null,
      winCondition: BoardgameWinCondition.fromJson(
        json['win_condition']?.toString(),
      ),
      useTeams: json['use_teams'] as bool? ?? grid?.hasTeams == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': DateFormat('yyyy-MM-dd').format(date),
        if (players.isNotEmpty) 'players': players,
        if (winner != null && winner!.isNotEmpty) 'winner': winner,
        if (trackScores && scoreGrid != null) 'score_grid': scoreGrid!.toJson(),
        if (scores != null && scores!.isNotEmpty) 'scores': scores,
        'track_scores': trackScores,
        'win_condition': winCondition.dbValue,
        if (useTeams) 'use_teams': true,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
      };

  String? get autoWinner {
    if (winCondition == BoardgameWinCondition.cooperative) return null;
    return scoreGrid?.autoWinnerName(winCondition);
  }

  String? get effectiveWinner {
    final manual = winner?.trim();
    if (manual != null && manual.isNotEmpty) return manual;
    return autoWinner;
  }

  String summaryLine() {
    final parts = <String>[];
    if (trackScores && scoreGrid != null && scoreGrid!.hasScores) {
      if (useTeams && scoreGrid!.hasTeams) {
        final tt = scoreGrid!.teamTotals();
        parts.add(
          tt.entries.map((e) => '${e.key} : ${e.value}').join(' · '),
        );
      } else {
        parts.add(scoreGrid!.totalsSummary());
      }
    } else if (scores != null && scores!.isNotEmpty) {
      parts.add(
        scores!.entries.map((e) => '${e.key} : ${e.value}').join(' · '),
      );
    } else if (players.isNotEmpty) {
      parts.add(players.join(', '));
    }
    final w = effectiveWinner;
    if (w != null && w.isNotEmpty) {
      parts.add(
        winCondition == BoardgameWinCondition.cooperative
            ? 'Coop réussi'
            : 'Gagnant : $w',
      );
    } else if (winCondition == BoardgameWinCondition.cooperative &&
        scoreGrid?.hasScores == true) {
      parts.add('Score coop : ${scoreGrid!.columnTotals().fold(0, (a, b) => a + b)}');
    }
    return parts.join('\n');
  }
}

List<BoardgamePlaySession> parseBoardgamePlays(Map<String, dynamic>? metadata) {
  final raw = metadata?['boardgame_plays'];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => BoardgamePlaySession.fromJson(Map<String, dynamic>.from(e)))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
}
