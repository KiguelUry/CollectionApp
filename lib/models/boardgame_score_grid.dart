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
          sum += round.malus ? -v : v;
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

  /// Phrase affichée dans Motif quand le gagnant est calculé.
  String? autoWinReason(
    BoardgameWinCondition condition, {
    int? targetScore,
    BoardgameScoreTemplate? template,
  }) {
    if (!hasScores) return null;
    if (condition == BoardgameWinCondition.customTemplate) {
      return template?.matchSummary(this);
    }
    if (condition != BoardgameWinCondition.highest &&
        condition != BoardgameWinCondition.lowest &&
        condition != BoardgameWinCondition.minimumThreshold) {
      return null;
    }
    final idx = winningColumnIndices(
      condition,
      targetScore: targetScore,
      template: template,
    );
    if (idx.isEmpty) return null;
    final score = _scoreOf(idx.first);
    return switch (condition) {
      BoardgameWinCondition.highest => 'Plus haut score : $score pts',
      BoardgameWinCondition.lowest => 'Plus petit score : $score pts',
      BoardgameWinCondition.minimumThreshold =>
        '$score pts (seuil >= ${targetScore ?? 0})',
      _ => null,
    };
  }

  int _scoreOf(int index) {
    if (hasTeams && index < teams.length) {
      final team = teams[index]?.trim();
      if (team != null && team.isNotEmpty) {
        return teamTotals()[team] ?? 0;
      }
    }
    final totals = columnTotals();
    return index < totals.length ? totals[index] : 0;
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

enum ScoreLineSign { bonus, malus }

class ScoreLineSpec {
  final String name;
  final ScoreLineSign sign;

  const ScoreLineSpec(this.name, {this.sign = ScoreLineSign.bonus});

  bool get malus => sign == ScoreLineSign.malus;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (malus) 'sign': 'malus',
      };

  static ScoreLineSpec fromJson(Object? raw) {
    if (raw is String) return ScoreLineSpec(raw.trim());
    if (raw is Map) {
      final name = raw['name']?.toString().trim() ?? '';
      final malus = raw['sign']?.toString() == 'malus' || raw['malus'] == true;
      return ScoreLineSpec(
        name,
        sign: malus ? ScoreLineSign.malus : ScoreLineSign.bonus,
      );
    }
    return const ScoreLineSpec('');
  }
}

enum ScoreRuleTarget { total, anyLine, filledLineCount, namedLine }

enum ScoreRuleOp { gte, eq, lte, gt, lt, highest, lowest }

class ScoreRule {
  final ScoreRuleTarget target;
  final ScoreRuleOp op;
  final int? value;
  final String? lineName;
  /// Pour « Nombre de catégories » : opérateur appliqué à chaque ligne.
  final ScoreRuleOp? cellOp;
  /// Seuil qu'une catégorie doit atteindre pour être comptée. Défaut : 1.
  final int? cellValue;

  const ScoreRule({
    required this.target,
    required this.op,
    this.value,
    this.lineName,
    this.cellOp,
    this.cellValue,
  });

  bool get countsCategories => target == ScoreRuleTarget.filledLineCount;

  ScoreRuleOp get effectiveCellOp => cellOp ?? ScoreRuleOp.gte;

  int get effectiveCellValue => cellValue ?? 1;

  bool get needsValue =>
      op != ScoreRuleOp.highest && op != ScoreRuleOp.lowest;

  String get opLabel => switch (op) {
        ScoreRuleOp.gte => '>=',
        ScoreRuleOp.eq => '=',
        ScoreRuleOp.lte => '<=',
        ScoreRuleOp.gt => '>',
        ScoreRuleOp.lt => '<',
        ScoreRuleOp.highest => 'Plus haut score',
        ScoreRuleOp.lowest => 'Plus petit score',
      };

  String get targetLabel => switch (target) {
        ScoreRuleTarget.total => 'Score total',
        ScoreRuleTarget.anyLine => 'N\'importe quelle catégorie',
        ScoreRuleTarget.filledLineCount => 'Nombre de catégories',
        ScoreRuleTarget.namedLine => 'Catégorie : ${lineName ?? ''}',
      };

  Map<String, dynamic> toJson() => {
        'target': target.name,
        'op': op.name,
        if (value != null) 'value': value,
        if (lineName != null && lineName!.isNotEmpty) 'line': lineName,
        if (countsCategories) ...{
          'cell_op': effectiveCellOp.name,
          'cell_value': effectiveCellValue,
        },
      };

  static ScoreRule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    ScoreRuleTarget? target;
    for (final t in ScoreRuleTarget.values) {
      if (t.name == raw['target']) target = t;
    }
    ScoreRuleOp? op;
    for (final o in ScoreRuleOp.values) {
      if (o.name == raw['op']) op = o;
    }
    if (target == null || op == null) return null;
    final valueRaw = raw['value'];
    final value = valueRaw is num
        ? valueRaw.round()
        : int.tryParse(valueRaw?.toString() ?? '');
    ScoreRuleOp? cellOp;
    for (final o in ScoreRuleOp.values) {
      if (o.name == raw['cell_op']) cellOp = o;
    }
    final cellRaw = raw['cell_value'];
    final cellValue = cellRaw is num
        ? cellRaw.round()
        : int.tryParse(cellRaw?.toString() ?? '');
    return ScoreRule(
      target: target,
      op: op,
      value: value,
      lineName: raw['line']?.toString(),
      cellOp: cellOp,
      cellValue: cellValue,
    );
  }
}

/// Modèle de fin de partie enregistré sur le jeu.
class BoardgameScoreTemplate {
  final List<ScoreLineSpec> lines;
  final List<ScoreRule> rules;
  /// Vrai = toutes les règles (ET). Faux = une seule suffit (OU).
  final bool matchAll;

  const BoardgameScoreTemplate({
    this.lines = const [],
    this.rules = const [],
    this.matchAll = false,
  });

  static const empty = BoardgameScoreTemplate();

  List<String> get lineNames => [
        for (final line in lines)
          if (line.name.trim().isNotEmpty) line.name.trim(),
      ];

  bool get hasRules => rules.isNotEmpty;

  Map<String, dynamic> toJson() => {
        if (lines.isNotEmpty)
          'lines': [for (final line in lines) line.toJson()],
        if (rules.isNotEmpty) 'rules': [for (final rule in rules) rule.toJson()],
        'match': matchAll ? 'and' : 'or',
        if (lineNames.isNotEmpty) 'line_names': lineNames,
      };

  static BoardgameScoreTemplate? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lines = (raw['lines'] as List?)
            ?.map(ScoreLineSpec.fromJson)
            .where((l) => l.name.isNotEmpty)
            .toList() ??
        (raw['line_names'] as List?)
            ?.map((e) => ScoreLineSpec(e.toString().trim()))
            .where((l) => l.name.isNotEmpty)
            .toList() ??
        <ScoreLineSpec>[];
    final rules = (raw['rules'] as List?)
            ?.map(ScoreRule.fromJson)
            .whereType<ScoreRule>()
            .toList() ??
        <ScoreRule>[];
    if (rules.isEmpty) {
      int? numOf(String key) {
        final v = raw[key];
        if (v is num) return v.round();
        return int.tryParse(v?.toString() ?? '');
      }

      final lineAt = numOf('line_at_least');
      final distinct = numOf('distinct_lines');
      final total = numOf('total_at_least');
      if (lineAt != null) {
        rules.add(
          ScoreRule(
            target: ScoreRuleTarget.anyLine,
            op: ScoreRuleOp.gte,
            value: lineAt,
          ),
        );
      }
      if (distinct != null) {
        rules.add(
          ScoreRule(
            target: ScoreRuleTarget.filledLineCount,
            op: ScoreRuleOp.gte,
            value: distinct,
          ),
        );
      }
      if (total != null) {
        rules.add(
          ScoreRule(
            target: ScoreRuleTarget.total,
            op: ScoreRuleOp.gte,
            value: total,
          ),
        );
      }
    }
    if (lines.isEmpty && rules.isEmpty) return null;
    return BoardgameScoreTemplate(
      lines: lines,
      rules: rules,
      matchAll: raw['match']?.toString() == 'and',
    );
  }

  static BoardgameScoreTemplate? fromMetadata(Map<String, dynamic>? metadata) {
    return fromJson(metadata?['score_template']);
  }

  bool columnMatches(BoardgameScoreGrid grid, int index) {
    if (!hasRules || index < 0 || index >= grid.players.length) return false;
    final hits = rules.map((rule) => _ruleMatches(grid, index, rule));
    if (matchAll) return hits.every((hit) => hit);
    return hits.any((hit) => hit);
  }

  /// Résumé des règles remplies par la première colonne gagnante.
  String? matchSummary(BoardgameScoreGrid grid) {
    final winners = grid.winningColumnIndices(
      BoardgameWinCondition.customTemplate,
      template: this,
    );
    if (winners.isEmpty) return null;
    final joiner = matchAll ? ' ET ' : ' OU ';
    final parts = <String>[];
    for (final index in winners) {
      final labels = <String>[];
      for (final rule in rules) {
        if (!_ruleMatches(grid, index, rule)) continue;
        labels.add(_rulePhrase(grid, index, rule));
      }
      if (labels.isNotEmpty) parts.add(labels.join(joiner));
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  bool _ruleMatches(BoardgameScoreGrid grid, int index, ScoreRule rule) {
    switch (rule.target) {
      case ScoreRuleTarget.total:
        final mine = _signedTotal(grid, index);
        return _compare(mine, rule, [
          for (var i = 0; i < grid.players.length; i++) _signedTotal(grid, i),
        ]);
      case ScoreRuleTarget.filledLineCount:
        final mine = _filledCount(grid, index, rule);
        return _compare(mine, rule, [
          for (var i = 0; i < grid.players.length; i++)
            _filledCount(grid, i, rule),
        ]);
      case ScoreRuleTarget.anyLine:
        if (rule.op == ScoreRuleOp.highest || rule.op == ScoreRuleOp.lowest) {
          for (var r = 0; r < grid.rounds.length; r++) {
            final mine = _raw(grid, r, index);
            if (mine == null) continue;
            final values = [
              for (var i = 0; i < grid.players.length; i++) _raw(grid, r, i),
            ];
            if (_isExtreme(mine, rule.op, values)) return true;
          }
          return false;
        }
        for (var r = 0; r < grid.rounds.length; r++) {
          final mine = _raw(grid, r, index);
          if (mine != null && _compare(mine, rule, const [])) {
            return true;
          }
        }
        return false;
      case ScoreRuleTarget.namedLine:
        final round = _roundIndex(grid, rule.lineName);
        if (round < 0) return false;
        final mine = _raw(grid, round, index);
        if (mine == null && rule.needsValue) return false;
        final values = [
          for (var i = 0; i < grid.players.length; i++) _raw(grid, round, i),
        ];
        return _compare(mine ?? 0, rule, values.whereType<int>().toList());
    }
  }

  String _rulePhrase(BoardgameScoreGrid grid, int index, ScoreRule rule) {
    if (rule.target == ScoreRuleTarget.anyLine && rule.needsValue) {
      for (var r = 0; r < grid.rounds.length; r++) {
        final mine = _raw(grid, r, index);
        if (mine != null && _compare(mine, rule, const [])) {
          final name = grid.rounds[r].label?.trim();
          final label = name == null || name.isEmpty ? 'Catégorie' : name;
          return '$label ${rule.opLabel} ${rule.value}';
        }
      }
    }
    if (rule.target == ScoreRuleTarget.filledLineCount && rule.needsValue) {
      return '${rule.opLabel} ${rule.value} catégories (valeur ${_opLabel(rule.effectiveCellOp)} ${rule.effectiveCellValue})';
    }
    if (!rule.needsValue) return '${rule.targetLabel} ${rule.opLabel}';
    return '${rule.targetLabel} ${rule.opLabel} ${rule.value ?? ''}';
  }

  bool _compare(int mine, ScoreRule rule, List<int> peers) {
    final value = rule.value ?? 0;
    return switch (rule.op) {
      ScoreRuleOp.gte => mine >= value,
      ScoreRuleOp.eq => mine == value,
      ScoreRuleOp.lte => mine <= value,
      ScoreRuleOp.gt => mine > value,
      ScoreRuleOp.lt => mine < value,
      ScoreRuleOp.highest => peers.isNotEmpty && mine >= peers.reduce((a, b) => a >= b ? a : b),
      ScoreRuleOp.lowest => peers.isNotEmpty && mine <= peers.reduce((a, b) => a <= b ? a : b),
    };
  }

  bool _isExtreme(int mine, ScoreRuleOp op, List<int?> values) {
    final nums = values.whereType<int>().toList();
    if (nums.isEmpty) return false;
    if (op == ScoreRuleOp.highest) {
      return mine >= nums.reduce((a, b) => a >= b ? a : b);
    }
    return mine <= nums.reduce((a, b) => a <= b ? a : b);
  }

  int _signedTotal(BoardgameScoreGrid grid, int index) {
    final totals = grid.columnTotals();
    return index < totals.length ? totals[index] : 0;
  }

  int _filledCount(BoardgameScoreGrid grid, int index, ScoreRule rule) {
    final probe = ScoreRule(
      target: ScoreRuleTarget.total,
      op: rule.effectiveCellOp,
      value: rule.effectiveCellValue,
    );
    var n = 0;
    for (final round in grid.rounds) {
      final raw = index < round.scores.length ? round.scores[index] : null;
      if (raw != null && _compare(raw, probe, const [])) n++;
    }
    return n;
  }

  String _opLabel(ScoreRuleOp op) => switch (op) {
        ScoreRuleOp.gte => '>=',
        ScoreRuleOp.eq => '=',
        ScoreRuleOp.lte => '<=',
        ScoreRuleOp.gt => '>',
        ScoreRuleOp.lt => '<',
        ScoreRuleOp.highest => 'Plus haut score',
        ScoreRuleOp.lowest => 'Plus petit score',
      };

  int? _raw(BoardgameScoreGrid grid, int round, int index) {
    if (round < 0 || round >= grid.rounds.length) return null;
    final scores = grid.rounds[round].scores;
    if (index < 0 || index >= scores.length) return null;
    return scores[index];
  }

  int _roundIndex(BoardgameScoreGrid grid, String? name) {
    final wanted = name?.trim() ?? '';
    if (wanted.isEmpty) return -1;
    for (var i = 0; i < grid.rounds.length; i++) {
      if ((grid.rounds[i].label ?? '').trim() == wanted) return i;
    }
    return -1;
  }
}

/// Modèle nommé, mémorisé sur le jeu (type de partie + grille + règles).
class NamedScorePreset {
  final String name;
  final BoardgameConfrontationType confrontation;
  final BoardgameScoreTemplate template;

  const NamedScorePreset({
    required this.name,
    required this.confrontation,
    required this.template,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'confrontation': confrontation.dbValue,
        'template': template.toJson(),
      };

  static NamedScorePreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString().trim() ?? '';
    final template = BoardgameScoreTemplate.fromJson(raw['template']);
    if (name.isEmpty || template == null) return null;
    return NamedScorePreset(
      name: name,
      confrontation: BoardgameConfrontationType.fromJson(
        raw['confrontation']?.toString(),
      ),
      template: template,
    );
  }

  static List<NamedScorePreset> listFrom(Map<String, dynamic>? metadata) {
    final raw = metadata?['score_presets'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (fromJson(item) != null) fromJson(item)!,
    ];
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
  /// Malus : la valeur saisie est soustraite du total.
  final bool malus;

  const BoardgameScoreRound({
    this.label,
    required this.scores,
    this.malus = false,
  });

  factory BoardgameScoreRound.fromJson(Map<String, dynamic> json) {
    final scores = (json['scores'] as List?)
            ?.map((e) => e == null ? null : (e as num).round())
            .toList() ??
        [];
    return BoardgameScoreRound(
      label: json['label'] as String?,
      scores: scores,
      malus: json['malus'] == true || json['sign']?.toString() == 'malus',
    );
  }

  Map<String, dynamic> toJson() => {
        if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
        'scores': scores,
        if (malus) 'malus': true,
      };

  BoardgameScoreRound copyWith({
    String? label,
    List<int?>? scores,
    bool? malus,
  }) {
    return BoardgameScoreRound(
      label: label ?? this.label,
      scores: scores ?? this.scores,
      malus: malus ?? this.malus,
    );
  }
}
