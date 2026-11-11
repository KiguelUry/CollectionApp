/// Grille de comptage de points (joueurs en colonnes, tours en lignes).
class BoardgameScoreGrid {
  final List<String> players;
  final List<BoardgameScoreRound> rounds;
  final List<String?> teams;
  final List<int?> playerColors;
  final Map<String, int> teamColorMap;
  final TeamScoreMode teamScoreMode;

  const BoardgameScoreGrid({
    required this.players,
    required this.rounds,
    this.teams = const [],
    this.playerColors = const [],
    this.teamColorMap = const {},
    this.teamScoreMode = TeamScoreMode.shared,
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
    final rawTeamColors = json['team_colors'] as Map?;
    final teamColorMap = <String, int>{};
    if (rawTeamColors != null) {
      for (final e in rawTeamColors.entries) {
        final v = e.value;
        if (v is num) teamColorMap[e.key.toString()] = v.round();
      }
    }
    return BoardgameScoreGrid(
      players: players,
      rounds: rounds,
      teams: teams,
      playerColors: playerColors,
      teamColorMap: teamColorMap,
      teamScoreMode: teamScoreMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'players': players,
        'rounds': rounds.map((r) => r.toJson()).toList(),
        if (teams.any((t) => t != null && t.trim().isNotEmpty))
          'teams': teams,
        if (playerColors.any((c) => c != null)) 'player_colors': playerColors,
        if (teamColorMap.isNotEmpty) 'team_colors': teamColorMap,
        if (teamScoreMode != TeamScoreMode.divided)
          'team_score_mode': teamScoreMode.dbValue,
      };

  List<String> get activePlayers =>
      players.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

  BoardgameScoreGrid remapPlayerNames(Map<String, String> map) {
    if (map.isEmpty) return this;
    String mapName(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return raw;
      return map[t.toLowerCase()] ?? raw;
    }

    return BoardgameScoreGrid(
      players: players.map(mapName).toList(),
      rounds: rounds,
      teams: teams,
      playerColors: playerColors,
      teamColorMap: teamColorMap,
      teamScoreMode: teamScoreMode,
    );
  }

  bool get hasScores => rounds.any((r) => r.scores.any((s) => s != null));

  bool get hasTeams =>
      teams.any((t) => t != null && t.trim().isNotEmpty);

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
  Set<int> winningColumnIndices(
    BoardgameWinCondition condition, {
    int? targetScore,
    BoardgameScoreTemplate? template,
  }) {
    if (condition == BoardgameWinCondition.cooperative ||
        condition == BoardgameWinCondition.noScore ||
        !hasScores) {
      return {};
    }
    if (condition == BoardgameWinCondition.exactTarget) {
      return _exactTargetWinners(targetScore);
    }
    if (condition == BoardgameWinCondition.minimumThreshold) {
      return _minimumThresholdWinners(targetScore);
    }
    if (condition == BoardgameWinCondition.customTemplate) {
      return _templateWinners(template);
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
      final bestVal = condition == BoardgameWinCondition.lowest
          ? eligible.map((e) => e.value).reduce((a, b) => a <= b ? a : b)
          : eligible.map((e) => e.value).reduce((a, b) => a >= b ? a : b);
      final winners = <int>{};
      for (var i = 0; i < teams.length; i++) {
        final team = teams[i]?.trim();
        if (team == null || team.isEmpty || !columnHasScores(i)) continue;
        final teamScore = tt[team];
        if (teamScore == bestVal) winners.add(i);
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

  /// Score exact : sous la cible = plus proche ; si tous dépassent = plus haut.
  Set<int> _exactTargetWinners(int? targetScore) {
    final target = targetScore;
    if (target == null) return {};

    if (hasTeams) {
      final tt = teamTotals();
      if (tt.isEmpty) return {};
      final entries = <MapEntry<String, int>>[];
      for (final e in tt.entries) {
        var hasScored = false;
        for (var i = 0; i < teams.length; i++) {
          if (teams[i]?.trim() == e.key && columnHasScores(i)) {
            hasScored = true;
            break;
          }
        }
        if (hasScored) entries.add(e);
      }
      if (entries.isEmpty) return {};
      final under = entries.where((e) => e.value <= target).toList();
      final pool = under.isNotEmpty ? under : entries;
      final best = under.isNotEmpty
          ? pool.map((e) => e.value).reduce((a, b) => a >= b ? a : b)
          : pool.map((e) => e.value).reduce((a, b) => a >= b ? a : b);
      final winnerTeams =
          pool.where((e) => e.value == best).map((e) => e.key).toSet();
      final winners = <int>{};
      for (var i = 0; i < teams.length; i++) {
        final team = teams[i]?.trim();
        if (team != null && winnerTeams.contains(team) && columnHasScores(i)) {
          winners.add(i);
        }
      }
      return winners;
    }

    final totals = columnTotals();
    final scored = <int>[];
    for (var i = 0; i < players.length; i++) {
      if (players[i].trim().isEmpty || !columnHasScores(i)) continue;
      scored.add(i);
    }
    if (scored.isEmpty) return {};
    final under = scored.where((i) => totals[i] <= target).toList();
    final pool = under.isNotEmpty ? under : scored;
    final best = pool.map((i) => totals[i]).reduce((a, b) => a >= b ? a : b);
    return pool.where((i) => totals[i] == best).toSet();
  }

  /// Plus haut total parmi ceux qui ont atteint le seuil. Personne sinon.
  Set<int> _minimumThresholdWinners(int? targetScore) {
    final target = targetScore;
    if (target == null) return {};
    if (hasTeams) {
      final tt = teamTotals();
      final eligible = tt.entries.where((e) => e.value >= target).toList();
      if (eligible.isEmpty) return {};
      final best = eligible.map((e) => e.value).reduce((a, b) => a >= b ? a : b);
      final winners = <int>{};
      for (var i = 0; i < teams.length; i++) {
        final team = teams[i]?.trim();
        if (team == null || team.isEmpty || !columnHasScores(i)) continue;
        if (tt[team] == best) winners.add(i);
      }
      return winners;
    }
    final totals = columnTotals();
    final eligible = <int>[];
    for (var i = 0; i < players.length; i++) {
      if (players[i].trim().isEmpty || !columnHasScores(i)) continue;
      if (totals[i] >= target) eligible.add(i);
    }
    if (eligible.isEmpty) return {};
    final best = eligible.map((i) => totals[i]).reduce((a, b) => a >= b ? a : b);
    return eligible.where((i) => totals[i] == best).toSet();
  }

  /// Une des conditions OU du modèle est remplie sur la colonne.
  Set<int> _templateWinners(BoardgameScoreTemplate? template) {
    final rules = template;
    if (rules == null || !rules.hasRules || !hasScores) return {};
    final winners = <int>{};
    for (var i = 0; i < players.length; i++) {
      if (players[i].trim().isEmpty) continue;
      if (rules.columnMatches(this, i)) winners.add(i);
    }
    return winners;
  }

  String? autoWinnerName(
    BoardgameWinCondition condition, {
    int? targetScore,
    BoardgameScoreTemplate? template,
  }) {
    final names = winnerNames(
      condition,
      targetScore: targetScore,
      template: template,
    );
    if (names.isEmpty) return null;
    if (names.length == 1) return names.first;
    return names.join(' & ');
  }

  /// Noms des gagnants (ex-aequo inclus).
  List<String> winnerNames(
    BoardgameWinCondition condition, {
    int? targetScore,
    BoardgameScoreTemplate? template,
  }) {
    if (condition == BoardgameWinCondition.cooperative ||
        condition == BoardgameWinCondition.noScore) {
      return [];
    }
    if (condition == BoardgameWinCondition.minimumThreshold ||
        condition == BoardgameWinCondition.customTemplate) {
      final idx = winningColumnIndices(
        condition,
        targetScore: targetScore,
        template: template,
      );
      if (hasTeams) {
        final names = <String>[];
        for (final i in idx) {
          final team = i < teams.length ? teams[i]?.trim() ?? '' : '';
          if (team.isNotEmpty && !names.contains(team)) names.add(team);
        }
        if (names.isNotEmpty) return names;
      }
      return idx
          .map((i) => players[i].trim())
          .where((n) => n.isNotEmpty)
          .toList();
    }
    if (condition == BoardgameWinCondition.exactTarget ||
        (hasTeams && hasScores && condition != BoardgameWinCondition.exactTarget)) {
      // Teams + exact handled via winningColumnIndices.
    }
    if (hasTeams &&
        hasScores &&
        condition != BoardgameWinCondition.exactTarget) {
      final tt = teamTotals();
      if (tt.isEmpty) return [];
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
      if (eligible.isEmpty) return [];
      final bestVal = condition == BoardgameWinCondition.lowest
          ? eligible.map((e) => e.value).reduce((a, b) => a <= b ? a : b)
          : eligible.map((e) => e.value).reduce((a, b) => a >= b ? a : b);
      return eligible
          .where((e) => e.value == bestVal)
          .map((e) => e.key)
          .toList();
    }
    final winners =
        winningColumnIndices(condition, targetScore: targetScore);
    if (hasTeams) {
      final names = <String>[];
      for (final i in winners) {
        final team = i < teams.length ? teams[i]?.trim() : null;
        if (team != null && team.isNotEmpty && !names.contains(team)) {
          names.add(team);
        }
      }
      if (names.isNotEmpty) return names;
    }
    return winners
        .map((i) => players[i].trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  /// Indices des colonnes en dernière place (ex-aequo inclus).
  Set<int> lastPlaceColumnIndices(BoardgameWinCondition condition) {
    if (condition == BoardgameWinCondition.cooperative ||
        condition == BoardgameWinCondition.noScore ||
        condition == BoardgameWinCondition.exactTarget ||
        condition == BoardgameWinCondition.minimumThreshold ||
        condition == BoardgameWinCondition.customTemplate ||
        !hasScores) {
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
      final worstVal = condition == BoardgameWinCondition.lowest
          ? eligible.map((e) => e.value).reduce((a, b) => a >= b ? a : b)
          : eligible.map((e) => e.value).reduce((a, b) => a <= b ? a : b);
      final losers = <int>{};
      for (var i = 0; i < teams.length; i++) {
        final team = teams[i]?.trim();
        if (team == null || team.isEmpty || !columnHasScores(i)) continue;
        if (tt[team] == worstVal) losers.add(i);
      }
      return losers;
    }

    final totals = columnTotals();
    var worstIdx = -1;
    var worstVal = condition == BoardgameWinCondition.lowest
        ? -(1 << 30)
        : (1 << 30);
    for (var i = 0; i < players.length; i++) {
      if (players[i].trim().isEmpty || !columnHasScores(i)) continue;
      final v = i < totals.length ? totals[i] : 0;
      final worse = condition == BoardgameWinCondition.lowest
          ? v > worstVal
          : v < worstVal;
      if (worse) {
        worstVal = v;
        worstIdx = i;
      }
    }
    if (worstIdx < 0) return {};
    final losers = <int>{worstIdx};
    for (var i = 0; i < players.length; i++) {
      if (i == worstIdx || players[i].trim().isEmpty || !columnHasScores(i)) continue;
      final v = i < totals.length ? totals[i] : 0;
      if (v == worstVal) losers.add(i);
    }
    return losers;
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
    while (nextTeams.length < count) {
      nextTeams.add(null);
    }
    if (nextTeams.length > count) nextTeams.removeRange(count, nextTeams.length);
    final nextColors = List<int?>.from(playerColors);
    while (nextColors.length < count) {
      nextColors.add(null);
    }
    if (nextColors.length > count) nextColors.removeRange(count, nextColors.length);
    final nextRounds = rounds.map((r) {
      final scores = List<int?>.from(r.scores);
      while (scores.length < count) {
        scores.add(null);
      }
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
        'divided' => TeamScoreMode.divided,
        _ => TeamScoreMode.shared,
      };

  String get dbValue => switch (this) {
        TeamScoreMode.divided => 'divided',
        TeamScoreMode.shared => 'shared',
      };
}

/// Type d'affrontement (indépendant de la condition de victoire).
enum BoardgameConfrontationType {
  freeForAll,
  teams,
  cooperative,
  /// Un joueur contre le camp des autres (2 équipes verrouillées).
  oneVsAll;

  String get label => switch (this) {
        BoardgameConfrontationType.freeForAll => 'Chacun pour soi',
        BoardgameConfrontationType.teams => 'En équipes',
        BoardgameConfrontationType.cooperative => 'Coopératif',
        BoardgameConfrontationType.oneVsAll => '1 contre tous',
      };

  String get shortLabel => switch (this) {
        BoardgameConfrontationType.freeForAll => 'Chacun pour soi',
        BoardgameConfrontationType.teams => 'En équipes',
        BoardgameConfrontationType.cooperative => 'Coopératif',
        BoardgameConfrontationType.oneVsAll => '1 contre tous',
      };

  static BoardgameConfrontationType fromJson(String? raw) {
    return switch (raw) {
      'teams' => BoardgameConfrontationType.teams,
      'cooperative' => BoardgameConfrontationType.cooperative,
      'one_vs_all' => BoardgameConfrontationType.oneVsAll,
      _ => BoardgameConfrontationType.freeForAll,
    };
  }

  String get dbValue => switch (this) {
        BoardgameConfrontationType.freeForAll => 'free_for_all',
        BoardgameConfrontationType.teams => 'teams',
        BoardgameConfrontationType.cooperative => 'cooperative',
        BoardgameConfrontationType.oneVsAll => 'one_vs_all',
      };
}

/// Modèle de fin de partie enregistré sur le jeu.
class BoardgameScoreTemplate {
  final List<String> lineNames;
  final int? lineAtLeast;
  final int? distinctLines;
  final int? totalAtLeast;

  const BoardgameScoreTemplate({
    this.lineNames = const [],
    this.lineAtLeast,
    this.distinctLines,
    this.totalAtLeast,
  });

  static const empty = BoardgameScoreTemplate();

  bool get hasRules =>
      lineAtLeast != null || distinctLines != null || totalAtLeast != null;

  Map<String, dynamic> toJson() => {
        if (lineNames.isNotEmpty) 'line_names': lineNames,
        if (lineAtLeast != null) 'line_at_least': lineAtLeast,
        if (distinctLines != null) 'distinct_lines': distinctLines,
        if (totalAtLeast != null) 'total_at_least': totalAtLeast,
      };

  static BoardgameScoreTemplate? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int? numOf(String key) {
      final v = raw[key];
      if (v is num) return v.round();
      return int.tryParse(v?.toString() ?? '');
    }

    final names = (raw['line_names'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];
    final template = BoardgameScoreTemplate(
      lineNames: names,
      lineAtLeast: numOf('line_at_least'),
      distinctLines: numOf('distinct_lines'),
      totalAtLeast: numOf('total_at_least'),
    );
    if (names.isEmpty && !template.hasRules) return null;
    return template;
  }

  static BoardgameScoreTemplate? fromMetadata(Map<String, dynamic>? metadata) {
    return fromJson(metadata?['score_template']);
  }

  /// Vrai si au moins une condition OU est remplie sur la colonne [index].
  bool columnMatches(BoardgameScoreGrid grid, int index) {
    final values = <int>[];
    for (final round in grid.rounds) {
      final raw = index < round.scores.length ? round.scores[index] : null;
      values.add(raw ?? 0);
    }
    final line = lineAtLeast != null && values.any((n) => n >= lineAtLeast!);
    final distinct = distinctLines != null &&
        values.where((n) => n >= 1).length >= distinctLines!;
    final total = totalAtLeast != null &&
        values.fold<int>(0, (a, b) => a + b) >= totalAtLeast!;
    if (!hasRules) return false;
    return (lineAtLeast != null && line) ||
        (distinctLines != null && distinct) ||
        (totalAtLeast != null && total);
  }
}

enum BoardgameWinCondition {
  highest,
  lowest,
  exactTarget,
  /// Plus haut score, seulement si le total atteint un seuil.
  minimumThreshold,
  /// Pas de grille : le gagnant est choisi, avec un motif libre.
  noScore,
  /// Lignes nommées + conditions OU, mémorisées sur le jeu.
  customTemplate,
  /// Legacy — préférer [BoardgameConfrontationType.cooperative].
  cooperative;

  String get label => switch (this) {
        BoardgameWinCondition.highest => 'Plus haut score',
        BoardgameWinCondition.lowest => 'Plus petit score',
        BoardgameWinCondition.exactTarget => 'Score exact',
        BoardgameWinCondition.minimumThreshold =>
          'Plus haut score (seuil minimum)',
        BoardgameWinCondition.noScore => 'Sans grille de points',
        BoardgameWinCondition.customTemplate => 'Modèle personnalisé (Template)',
        BoardgameWinCondition.cooperative => 'Mode coopératif',
      };

  String get shortLabel => label;

  /// Menu courant. « Score exact » reste lisible sur les anciennes parties.
  static List<BoardgameWinCondition> selectableFor(
    BoardgameWinCondition current,
  ) {
    const base = <BoardgameWinCondition>[
      BoardgameWinCondition.highest,
      BoardgameWinCondition.lowest,
      BoardgameWinCondition.minimumThreshold,
      BoardgameWinCondition.noScore,
      BoardgameWinCondition.customTemplate,
    ];
    if (current == BoardgameWinCondition.exactTarget) {
      return [
        BoardgameWinCondition.highest,
        BoardgameWinCondition.lowest,
        BoardgameWinCondition.exactTarget,
        ...base.skip(2),
      ];
    }
    return base;
  }

  static BoardgameWinCondition fromJson(String? raw) {
    return switch (raw) {
      'lowest' => BoardgameWinCondition.lowest,
      'exact' || 'exact_target' => BoardgameWinCondition.exactTarget,
      'min_threshold' || 'minimum_threshold' =>
        BoardgameWinCondition.minimumThreshold,
      'no_score' || 'unscored' => BoardgameWinCondition.noScore,
      'custom_template' || 'template' => BoardgameWinCondition.customTemplate,
      'cooperative' => BoardgameWinCondition.cooperative,
      _ => BoardgameWinCondition.highest,
    };
  }

  String get dbValue => switch (this) {
        BoardgameWinCondition.highest => 'highest',
        BoardgameWinCondition.lowest => 'lowest',
        BoardgameWinCondition.exactTarget => 'exact_target',
        BoardgameWinCondition.minimumThreshold => 'min_threshold',
        BoardgameWinCondition.noScore => 'no_score',
        BoardgameWinCondition.customTemplate => 'custom_template',
        BoardgameWinCondition.cooperative => 'cooperative',
      };
}

enum BoardgamePlayStatus {
  finished,
  inProgress;

  String get label => switch (this) {
        BoardgamePlayStatus.finished => 'Terminée',
        BoardgamePlayStatus.inProgress => 'En cours',
      };

  static BoardgamePlayStatus fromJson(String? raw) {
    return switch (raw) {
      'in_progress' || 'playing' => BoardgamePlayStatus.inProgress,
      _ => BoardgamePlayStatus.finished,
    };
  }

  String get dbValue => switch (this) {
        BoardgamePlayStatus.finished => 'finished',
        BoardgamePlayStatus.inProgress => 'in_progress',
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
