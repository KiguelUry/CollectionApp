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
  final bool? coopVictory;
  final int? coopTeamCount;

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
    this.coopVictory,
    this.coopTeamCount,
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
      coopVictory: json['coop_victory'] as bool?,
      coopTeamCount: json['coop_team_count'] as int?,
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
        if (coopVictory != null) 'coop_victory': coopVictory,
        if (coopTeamCount != null) 'coop_team_count': coopTeamCount,
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
      if (useTeams && scoreGrid != null && scoreGrid!.hasTeams) {
        final members = <String>[];
        for (var i = 0; i < scoreGrid!.players.length; i++) {
          if (scoreGrid!.teams.length > i &&
              scoreGrid!.teams[i]?.trim() == w.trim()) {
            final n = scoreGrid!.players[i].trim();
            if (n.isNotEmpty) members.add(n);
          }
        }
        if (members.isNotEmpty) {
          parts.add(
            'Équipe gagnante : $w (Joueurs : ${_formatNameList(members)})',
          );
        } else {
          parts.add('Gagnant : $w');
        }
      } else {
        parts.add(
          winCondition == BoardgameWinCondition.cooperative
              ? 'Coop réussi'
              : 'Gagnant : $w',
        );
      }
    } else if (winCondition == BoardgameWinCondition.cooperative) {
      if (coopVictory == true) {
        if (players.isNotEmpty) {
          parts.add(
            'Victoire coop (${_formatNameList(players)})',
          );
        } else {
          parts.add('Victoire coop');
        }
      } else if (coopVictory == false) {
        parts.add('Défaite coop');
      } else if (scoreGrid?.hasScores == true) {
        parts.add(
          'Score coop : ${scoreGrid!.columnTotals().fold(0, (a, b) => a + b)}',
        );
      }
    }
    return parts.join('\n');
  }

  static String _formatNameList(List<String> names) {
    if (names.length <= 1) return names.join();
    if (names.length == 2) return '${names[0]} et ${names[1]}';
    return '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}';
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
