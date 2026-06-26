/// Grille de comptage de points (joueurs en colonnes, tours en lignes).
class BoardgameScoreGrid {
  final List<String> players;
  final List<BoardgameScoreRound> rounds;
  final List<String?> teams;
  final List<int?> playerColors;
  final TeamScoreMode teamScoreMode;

  const BoardgameScoreGrid({
    required this.players,
    required this.rounds,
    this.teams = const [],
    this.playerColors = const [],
    this.teamScoreMode = TeamScoreMode.divided,
  });

  /// Nombre de colonnes joueur par défaut selon la fiche BGG.
  static int defaultPlayerCount({int? minPlayers, int? maxPlayers}) {
    final min = minPlayers ?? 2;
    final max = maxPlayers ?? min;
    if (max <= 4) return min.clamp(1, 12);
    if (min >= 4) return 4.clamp(1, 12);
    if (min <= 4 && max >= 4) return 4.clamp(1, 12);
    return 2.clamp(1, 12);
  }

  factory BoardgameScoreGrid.empty({
    int playerCount = 2,
    int roundCount = 3,
  }) {
    final players = List.generate(playerCount, (_) => '');
    final rounds = List.generate(
      roundCount,
      (i) => BoardgameScoreRound(
        label: 'Tour ${i + 1}',
        scores: List.filled(playerCount, null),
      ),
    );
    return BoardgameScoreGrid(
      players: players,
      rounds: rounds,
      teams: List.filled(playerCount, null),
      playerColors: List.filled(playerCount, null),
    );
  }

  factory BoardgameScoreGrid.fromJson(Map<String, dynamic> json) {
    final players = (json['players'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final rawRounds = json['rounds'] as List? ?? [];
    final rounds = rawRounds
        .whereType<Map>()
        .map((r) => BoardgameScoreRound.fromJson(Map<String, dynamic>.from(r)))
        .toList();
    final rawTeams = json['teams'] as List?;
    final teams = rawTeams != null
        ? rawTeams.map((e) => e?.toString()).toList()
        : List<String?>.filled(players.length, null);
    final rawColors = json['player_colors'] as List?;
    final playerColors = rawColors != null
        ? rawColors.map((e) => e == null ? null : (e as num).round()).toList()
        : List<int?>.filled(players.length, null);
    final teamScoreMode = TeamScoreMode.fromJson(
      json['team_score_mode']?.toString(),
    );
    return BoardgameScoreGrid(
      players: players,
      rounds: rounds,
      teams: teams,
      playerColors: playerColors,
      teamScoreMode: teamScoreMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'players': players,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        if (teams.any((t) => t != null && t!.trim().isNotEmpty))
          'teams': teams,
        if (playerColors.any((c) => c != null)) 'player_colors': playerColors,
        if (teamScoreMode != TeamScoreMode.divided)
          'team_score_mode': teamScoreMode.dbValue,
      };

  List<String> get activePlayers =>
      players.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

  bool get hasScores => rounds.any((r) => r.scores.any((s) => s != null));

  bool get hasTeams =>
      teams.any((t) => t != null && t!.trim().isNotEmpty);

  bool columnHasScores(int col) {
    for (final round in rounds) {
      if (col < round.scores.length && round.scores[col] != null) return true;
    }
    return false;
  }

  /// Totaux par colonne (somme des tours).
  List<int> columnTotals() {
    if (players.isEmpty) return [];
    return List.generate(players.length, (col) {
      var sum = 0;
      var hasAny = false;
      for (final round in rounds) {
        if (col >= round.scores.length) continue;
        final v = round.scores[col];
        if (v != null) {
          sum += v;
          hasAny = true;
        }
      }
      return hasAny ? sum : 0;
    });
  }

  /// Totaux cumulés par équipe (nom d'équipe → score).
  Map<String, int> teamTotals() {
    final totals = columnTotals();
    final out = <String, int>{};
    for (var i = 0; i < players.length; i++) {
      final team = i < teams.length ? teams[i]?.trim() : null;
      if (team == null || team.isEmpty) continue;
      final t = i < totals.length ? totals[i] : 0;
      out[team] = (out[team] ?? 0) + t;
    }
    return out;
  }

  /// Indices des colonnes gagnantes selon la condition de victoire.
  Set<int> winningColumnIndices(BoardgameWinCondition condition) {
    if (condition == BoardgameWinCondition.cooperative || !hasScores) {
      return {};
    }
    if (hasTeams) {
      final tt = teamTotals();
      if (tt.isEmpty) return {};
      final eligible = tt.entries
          .where((e) => e.key.isNotEmpty)
          .where((e) {
            for (var i = 0; i < teams.length; i++) {
              if (teams[i]?.trim() == e.key && columnHasScores(i)) return true;
            }
            return false;
          })
          .toList();
      if (eligible.isEmpty) return {};
      final best = condition == BoardgameWinCondition.lowest
          ? eligible.reduce((a, b) => a.value <= b.value ? a : b)
          : eligible.reduce((a, b) => a.value >= b.value ? a : b);
      final winners = <int>{};
      for (var i = 0; i < teams.length; i++) {
        if (teams[i]?.trim() == best.key && columnHasScores(i)) {
          winners.add(i);
        }
      }
      return winners;
    }

    final totals = columnTotals();
    var bestIdx = -1;
    var bestVal = condition == BoardgameWinCondition.lowest
        ? (1 << 30)
        : -(1 << 30);
    for (var i = 0; i < players.length; i++) {
      if (players[i].trim().isEmpty || !columnHasScores(i)) continue;
      final v = i < totals.length ? totals[i] : 0;
      final better = condition == BoardgameWinCondition.lowest
          ? v < bestVal
          : v > bestVal;
      if (better) {
        bestVal = v;
        bestIdx = i;
      }
    }
    if (bestIdx < 0) return {};
    // Égalités : toutes les colonnes au même score optimal.
    final winners = <int>{bestIdx};
    for (var i = 0; i < players.length; i++) {
      if (i == bestIdx || players[i].trim().isEmpty || !columnHasScores(i)) {
        continue;
      }
      final v = i < totals.length ? totals[i] : 0;
      if (v == bestVal) winners.add(i);
    }
    return winners;
  }

  String? autoWinnerName(BoardgameWinCondition condition) {
    if (condition == BoardgameWinCondition.cooperative) return null;
    if (hasTeams && hasScores) {
      final tt = teamTotals();
      if (tt.isEmpty) return null;
      final eligible = <MapEntry<String, int>>[];
      for (final e in tt.entries) {
        var hasScored = false;
        for (var i = 0; i < teams.length; i++) {
          if (teams[i]?.trim() == e.key && columnHasScores(i)) {
            hasScored = true;
            break;
          }
        }
        if (hasScored) eligible.add(e);
      }
      if (eligible.isEmpty) return null;
      final entry = condition == BoardgameWinCondition.lowest
          ? eligible.reduce((a, b) => a.value <= b.value ? a : b)
          : eligible.reduce((a, b) => a.value >= b.value ? a : b);
      return entry.key;
    }
    final winners = winningColumnIndices(condition);
    if (winners.isEmpty) return null;
    return players[winners.first].trim();
  }

  /// Résumé « Alice : 12 · Bob : 8 » pour l'historique.
  String totalsSummary() {
    final names = players;
    final totals = columnTotals();
    final parts = <String>[];
    for (var i = 0; i < names.length; i++) {
      final name = names[i].trim();
      if (name.isEmpty) continue;
      if (!hasScores) {
        parts.add(name);
        continue;
      }
      final t = i < totals.length ? totals[i] : 0;
      parts.add('$name : $t');
    }
    return parts.join(' · ');
  }

  /// Map legacy scores pour rétrocompat.
  Map<String, int> toLegacyScores() {
    final totals = columnTotals();
    final out = <String, int>{};
    for (var i = 0; i < players.length; i++) {
      final name = players[i].trim();
      if (name.isEmpty) continue;
      if (hasScores && i < totals.length) out[name] = totals[i];
    }
    return out;
  }

  BoardgameScoreGrid ensureColumnCount(int count) {
    final nextPlayers = List<String>.from(players);
    while (nextPlayers.length < count) {
      nextPlayers.add('');
    }
    if (nextPlayers.length > count) {
      nextPlayers.removeRange(count, nextPlayers.length);
    }
    final nextTeams = List<String?>.from(teams);
    while (nextTeams.length < count) nextTeams.add(null);
    if (nextTeams.length > count) nextTeams.removeRange(count, nextTeams.length);
    final nextColors = List<int?>.from(playerColors);
    while (nextColors.length < count) nextColors.add(null);
    if (nextColors.length > count) nextColors.removeRange(count, nextColors.length);
    final nextRounds = rounds.map((r) {
      final scores = List<int?>.from(r.scores);
      while (scores.length < count) scores.add(null);
      if (scores.length > count) scores.removeRange(count, scores.length);
      return r.copyWith(scores: scores);
    }).toList();
    return BoardgameScoreGrid(
      players: nextPlayers,
      rounds: nextRounds,
      teams: nextTeams,
      playerColors: nextColors,
      teamScoreMode: teamScoreMode,
    );
  }

  BoardgameScoreGrid copyWith({
    List<String>? players,
    List<BoardgameScoreRound>? rounds,
    List<String?>? teams,
    List<int?>? playerColors,
    TeamScoreMode? teamScoreMode,
  }) {
    return BoardgameScoreGrid(
      players: players ?? this.players,
      rounds: rounds ?? this.rounds,
      teams: teams ?? this.teams,
      playerColors: playerColors ?? this.playerColors,
      teamScoreMode: teamScoreMode ?? this.teamScoreMode,
    );
  }

  /// Colonnes affichées en mode scores communs par équipe.
  List<String> uniqueTeamNames() {
    final out = <String>[];
    for (final t in teams) {
      final n = t?.trim() ?? '';
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
    }
    return out;
  }

  /// Indices joueurs pour une équipe donnée.
  List<int> indicesForTeam(String team) {
    final out = <int>[];
    for (var i = 0; i < teams.length; i++) {
      if (teams[i]?.trim() == team) out.add(i);
    }
    return out;
  }
}

enum TeamScoreMode {
  divided,
  shared;

  String get label => switch (this) {
        TeamScoreMode.divided => 'Points par joueur',
        TeamScoreMode.shared => 'Points communs par équipe',
      };

  static TeamScoreMode fromJson(String? raw) => switch (raw) {
        'shared' => TeamScoreMode.shared,
        _ => TeamScoreMode.divided,
      };

  String get dbValue => switch (this) {
        TeamScoreMode.divided => 'divided',
        TeamScoreMode.shared => 'shared',
      };
}

enum BoardgameWinCondition {
  highest,
  lowest,
  cooperative;

  String get label => switch (this) {
        BoardgameWinCondition.highest => 'Plus haut score gagne',
        BoardgameWinCondition.lowest => 'Plus bas score gagne',
        BoardgameWinCondition.cooperative => 'Mode coopératif',
      };

  static BoardgameWinCondition fromJson(String? raw) {
    return switch (raw) {
      'lowest' => BoardgameWinCondition.lowest,
      'cooperative' => BoardgameWinCondition.cooperative,
      _ => BoardgameWinCondition.highest,
    };
  }

  String get dbValue => switch (this) {
        BoardgameWinCondition.highest => 'highest',
        BoardgameWinCondition.lowest => 'lowest',
        BoardgameWinCondition.cooperative => 'cooperative',
      };
}

class BoardgameScoreRound {
  final String? label;
  final List<int?> scores;

  const BoardgameScoreRound({this.label, required this.scores});

  factory BoardgameScoreRound.fromJson(Map<String, dynamic> json) {
    final scores = (json['scores'] as List?)
            ?.map((e) => e == null ? null : (e as num).round())
            .toList() ??
        [];
    return BoardgameScoreRound(
      label: json['label'] as String?,
      scores: scores,
    );
  }

  Map<String, dynamic> toJson() => {
        if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
        'scores': scores,
      };

  BoardgameScoreRound copyWith({String? label, List<int?>? scores}) {
    return BoardgameScoreRound(
      label: label ?? this.label,
      scores: scores ?? this.scores,
    );
  }
}
