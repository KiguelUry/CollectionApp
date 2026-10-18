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
  final BoardgameConfrontationType confrontationType;
  final bool useTeams;
  final bool? coopVictory;
  final int? coopTeamCount;
  final int? targetScore;
  final BoardgamePlayStatus status;
  /// Heure d'ajout (tri stable quand plusieurs parties ont la même date).
  final DateTime? createdAt;
  /// Identifiant stable d'une partie partagée entre amis (anti-doublon).
  final String? shareId;
  /// Gagnant imposé à la main (sinon dérivé de la grille).
  final bool winnerManuallyForced;

  const BoardgamePlaySession({
    required this.date,
    required this.players,
    this.winner,
    this.scores,
    this.scoreGrid,
    this.notes,
    this.trackScores = false,
    this.winCondition = BoardgameWinCondition.highest,
    this.confrontationType = BoardgameConfrontationType.freeForAll,
    this.useTeams = false,
    this.coopVictory,
    this.coopTeamCount,
    this.targetScore,
    this.status = BoardgamePlayStatus.finished,
    this.createdAt,
    this.shareId,
    this.winnerManuallyForced = false,
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

    DateTime? createdAt;
    final rawCreated = json['created_at']?.toString();
    if (rawCreated != null && rawCreated.isNotEmpty) {
      createdAt = DateTime.tryParse(rawCreated);
    }

    final rawWin = json['win_condition']?.toString();
    var winCondition = BoardgameWinCondition.fromJson(rawWin);
    final useTeamsFlag =
        json['use_teams'] as bool? ?? grid?.hasTeams == true;

    BoardgameConfrontationType confrontation;
    if (json['confrontation_type'] != null) {
      confrontation = BoardgameConfrontationType.fromJson(
        json['confrontation_type']?.toString(),
      );
    } else if (winCondition == BoardgameWinCondition.cooperative) {
      confrontation = BoardgameConfrontationType.cooperative;
      winCondition = BoardgameWinCondition.highest;
    } else if (useTeamsFlag) {
      confrontation = BoardgameConfrontationType.teams;
    } else {
      confrontation = BoardgameConfrontationType.freeForAll;
    }

    final targetRaw = json['target_score'];
    final targetScore = targetRaw is num
        ? targetRaw.round()
        : int.tryParse(targetRaw?.toString() ?? '');

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
      winCondition: winCondition,
      confrontationType: confrontation,
      useTeams: confrontation == BoardgameConfrontationType.teams ||
          (confrontation == BoardgameConfrontationType.cooperative &&
              ((json['coop_team_count'] as num?)?.toInt() ?? 1) > 1) ||
          useTeamsFlag,
      coopVictory: json['coop_victory'] as bool?,
      coopTeamCount: json['coop_team_count'] as int?,
      targetScore: targetScore,
      status: BoardgamePlayStatus.fromJson(json['status']?.toString()),
      createdAt: createdAt,
      shareId: (json['share_id']?.toString().trim().isEmpty ?? true)
          ? null
          : json['share_id'].toString().trim(),
      winnerManuallyForced: json['winner_manually_forced'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': DateFormat('yyyy-MM-dd').format(date),
        if (createdAt != null)
          'created_at': createdAt!.toUtc().toIso8601String(),
        if (players.isNotEmpty) 'players': players,
        if (winner != null && winner!.isNotEmpty) 'winner': winner,
        if (trackScores && scoreGrid != null) 'score_grid': scoreGrid!.toJson(),
        if (scores != null && scores!.isNotEmpty) 'scores': scores,
        'track_scores': trackScores,
        'win_condition': winCondition.dbValue,
        'confrontation_type': confrontationType.dbValue,
        'status': status.dbValue,
        if (useTeams ||
            confrontationType == BoardgameConfrontationType.teams)
          'use_teams': true,
        if (coopVictory != null) 'coop_victory': coopVictory,
        if (coopTeamCount != null) 'coop_team_count': coopTeamCount,
        if (targetScore != null) 'target_score': targetScore,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
        if (shareId != null) 'share_id': shareId,
        if (winnerManuallyForced) 'winner_manually_forced': true,
      };

  bool get isCooperative =>
      confrontationType == BoardgameConfrontationType.cooperative ||
      winCondition == BoardgameWinCondition.cooperative;

  bool get isInProgress => status == BoardgamePlayStatus.inProgress;

  String? get autoWinner {
    if (isCooperative) return null;
    return scoreGrid?.autoWinnerName(
      winCondition,
      targetScore: targetScore,
    );
  }

  String? get effectiveWinner {
    if (isCooperative) return winner;
    final computed = autoWinner;
    if (winnerManuallyForced) {
      final manual = winner?.trim();
      if (manual != null && manual.isNotEmpty) return manual;
      return computed;
    }
    if (computed != null && computed.isNotEmpty) return computed;
    final legacy = winner?.trim();
    return legacy != null && legacy.isNotEmpty ? legacy : null;
  }

  /// Ligne scores / joueurs uniquement (sans gagnant).
  String? get scoresLine {
    if (trackScores && scoreGrid != null && scoreGrid!.hasScores) {
      if (useTeams && scoreGrid!.hasTeams) {
        final tt = scoreGrid!.teamTotals();
        return tt.entries.map((e) => '${e.key} : ${e.value}').join(' · ');
      }
      return scoreGrid!.totalsSummary();
    }
    if (scores != null && scores!.isNotEmpty) {
      return scores!.entries.map((e) => '${e.key} : ${e.value}').join(' · ');
    }
    if (players.isNotEmpty) return players.join(', ');
    return null;
  }

  /// Ligne gagnant(s) / coop (sans scores).
  String? get winnerLine {
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
          return 'Équipe gagnante : $w (Joueurs : ${_formatNameList(members)})';
        }
        return 'Gagnant : $w';
      }
      if (w.contains('&')) return 'Gagnants : $w';
      return isCooperative ? 'Coop réussi' : 'Gagnant : $w';
    }
    if (scoreGrid != null && scoreGrid!.hasScores) {
      final names = scoreGrid!.winnerNames(
        winCondition,
        targetScore: targetScore,
      );
      if (names.length > 1) return 'Gagnants : ${names.join(' & ')}';
      if (names.length == 1) return 'Gagnant : ${names.first}';
    } else if (isCooperative) {
      if (coopVictory == true) {
        if (players.isNotEmpty) {
          return 'Victoire coop (${_formatNameList(players)})';
        }
        return 'Victoire coop';
      }
      if (coopVictory == false) return 'Défaite coop';
      if (scoreGrid?.hasScores == true) {
        return 'Score coop : ${scoreGrid!.columnTotals().fold(0, (a, b) => a + b)}';
      }
    }
    return null;
  }

  String summaryLine() {
    final parts = <String>[];
    final scores = scoresLine;
    if (scores != null && scores.isNotEmpty) parts.add(scores);
    final win = winnerLine;
    if (win != null && win.isNotEmpty) parts.add(win);
    return parts.join('\n');
  }

  BoardgamePlaySession copyWith({
    DateTime? date,
    List<String>? players,
    String? winner,
    bool clearWinner = false,
    Map<String, int>? scores,
    BoardgameScoreGrid? scoreGrid,
    String? notes,
    bool? trackScores,
    BoardgameWinCondition? winCondition,
    BoardgameConfrontationType? confrontationType,
    bool? useTeams,
    bool? coopVictory,
    int? coopTeamCount,
    int? targetScore,
    bool clearTarget = false,
    BoardgamePlayStatus? status,
    DateTime? createdAt,
    String? shareId,
    bool? winnerManuallyForced,
    bool clearWinnerManuallyForced = false,
  }) {
    return BoardgamePlaySession(
      date: date ?? this.date,
      players: players ?? this.players,
      winner: clearWinner ? null : (winner ?? this.winner),
      scores: scores ?? this.scores,
      scoreGrid: scoreGrid ?? this.scoreGrid,
      notes: notes ?? this.notes,
      trackScores: trackScores ?? this.trackScores,
      winCondition: winCondition ?? this.winCondition,
      confrontationType: confrontationType ?? this.confrontationType,
      useTeams: useTeams ?? this.useTeams,
      coopVictory: coopVictory ?? this.coopVictory,
      coopTeamCount: coopTeamCount ?? this.coopTeamCount,
      targetScore: clearTarget ? null : (targetScore ?? this.targetScore),
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      shareId: shareId ?? this.shareId,
      winnerManuallyForced: clearWinnerManuallyForced
          ? false
          : (winnerManuallyForced ?? this.winnerManuallyForced),
    );
  }

  /// Déduit si le gagnant enregistré diffère du calcul automatique (legacy).
  /// Préremplit le champ « forcer manuellement » à l'édition (pas les parties legacy).
  static bool inferWinnerManuallyForced(BoardgamePlaySession s) {
    if (s.winnerManuallyForced) return true;
    if (s.isCooperative) return false;
    final manual = s.winner?.trim();
    if (manual == null || manual.isEmpty) return false;
    if (!s.trackScores || s.scoreGrid?.hasScores != true) return true;
    return false;
  }

  /// Remplace les noms de joueurs selon [map] (clés en minuscules).
  BoardgamePlaySession remapPlayerNames(Map<String, String> map) {
    if (map.isEmpty) return this;
    String mapName(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return raw;
      return map[t.toLowerCase()] ?? raw;
    }

    final nextPlayers = players.map(mapName).toList();
    String? nextWinner = winner;
    if (nextWinner != null && nextWinner.trim().isNotEmpty) {
      // Winner peut être "A & B"
      if (nextWinner.contains('&')) {
        nextWinner = nextWinner
            .split('&')
            .map((p) => mapName(p.trim()))
            .join(' & ');
      } else {
        nextWinner = mapName(nextWinner);
      }
    }
    Map<String, int>? nextScores;
    if (scores != null) {
      nextScores = {};
      for (final e in scores!.entries) {
        nextScores[mapName(e.key)] = e.value;
      }
    }
    final nextGrid = scoreGrid?.remapPlayerNames(map);
    return copyWith(
      players: nextPlayers,
      winner: nextWinner,
      scores: nextScores,
      scoreGrid: nextGrid,
    );
  }

  static String _formatNameList(List<String> names) {
    if (names.length <= 1) return names.join();
    if (names.length == 2) return '${names[0]} et ${names[1]}';
    return '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}';
  }
}

/// Tri décroissant : date, puis heure d'ajout, puis ordre d'enregistrement.
int compareBoardgamePlaySessions(
  BoardgamePlaySession a,
  int indexA,
  BoardgamePlaySession b,
  int indexB,
) {
  final byDate = b.date.compareTo(a.date);
  if (byDate != 0) return byDate;

  final ca = a.createdAt;
  final cb = b.createdAt;
  if (ca != null && cb != null) {
    final byCreated = cb.compareTo(ca);
    if (byCreated != 0) return byCreated;
  } else if (ca != null) {
    return -1;
  } else if (cb != null) {
    return 1;
  }

  return indexA.compareTo(indexB);
}

List<BoardgamePlaySession> parseBoardgamePlays(Map<String, dynamic>? metadata) {
  final raw = metadata?['boardgame_plays'];
  if (raw is! List) return [];
  final indexed = raw.whereType<Map>().toList().asMap().entries.map((entry) {
    return (
      index: entry.key,
      session: BoardgamePlaySession.fromJson(
        Map<String, dynamic>.from(entry.value),
      ),
    );
  }).toList();
  indexed.sort(
    (a, b) => compareBoardgamePlaySessions(
      a.session,
      a.index,
      b.session,
      b.index,
    ),
  );
  return indexed.map((e) => e.session).toList();
}
