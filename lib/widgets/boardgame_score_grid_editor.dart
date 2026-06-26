import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/boardgame_score_grid.dart';

/// Éditeur visuel de grille de points (joueurs × tours + totaux).
/// État local : pas de notification parent à chaque frappe (évite perte de focus).
class BoardgameScoreGridEditor extends StatefulWidget {
  final BoardgameScoreGrid initialGrid;
  final bool enabled;
  final bool useTeams;
  final BoardgameWinCondition winCondition;
  final ValueChanged<bool>? onTeamsChanged;
  final Future<String?> Function(int columnIndex)? onPickPlayer;

  const BoardgameScoreGridEditor({
    super.key,
    required this.initialGrid,
    this.enabled = true,
    this.useTeams = false,
    this.winCondition = BoardgameWinCondition.highest,
    this.onTeamsChanged,
    this.onPickPlayer,
  });

  @override
  BoardgameScoreGridEditorState createState() =>
      BoardgameScoreGridEditorState();
}

class BoardgameScoreGridEditorState extends State<BoardgameScoreGridEditor> {
  late List<TextEditingController> _playerControllers;
  late List<TextEditingController> _roundLabelControllers;
  late List<List<TextEditingController>> _cellControllers;
  late List<TextEditingController> _teamControllers;
  late int _revision;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.initialGrid);
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _initControllers(BoardgameScoreGrid grid) {
    _playerControllers = grid.players
        .map((p) => TextEditingController(text: p))
        .toList();
    _roundLabelControllers = grid.rounds
        .map((r) => TextEditingController(text: r.label ?? ''))
        .toList();
    _cellControllers = grid.rounds
        .map(
          (r) => r.scores
              .map((s) => TextEditingController(text: s?.toString() ?? ''))
              .toList(),
        )
        .toList();
    final teams = grid.teams.length == grid.players.length
        ? grid.teams
        : List<String?>.filled(grid.players.length, null);
    _teamControllers =
        teams.map((t) => TextEditingController(text: t ?? '')).toList();
    _revision = 0;
  }

  void _disposeControllers() {
    for (final c in _playerControllers) {
      c.dispose();
    }
    for (final c in _roundLabelControllers) {
      c.dispose();
    }
    for (final row in _cellControllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final c in _teamControllers) {
      c.dispose();
    }
  }

  /// Lit la grille courante depuis les contrôleurs (appelé à l'enregistrement).
  BoardgameScoreGrid buildGrid() {
    final players = _playerControllers.map((c) => c.text).toList();
    final teams = _teamControllers.map((c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }).toList();
    final rounds = <BoardgameScoreRound>[];
    for (var r = 0; r < _roundLabelControllers.length; r++) {
      final scores = <int?>[];
      for (var c = 0; c < _playerControllers.length; c++) {
        final raw = _cellControllers[r][c].text.trim();
        scores.add(raw.isEmpty ? null : int.tryParse(raw));
      }
      rounds.add(
        BoardgameScoreRound(
          label: _roundLabelControllers[r].text.trim().isEmpty
              ? null
              : _roundLabelControllers[r].text.trim(),
          scores: scores,
        ),
      );
    }
    return BoardgameScoreGrid(players: players, rounds: rounds, teams: teams);
  }

  void _localRefresh() => setState(() => _revision++);

  void _setColumnCount(int count) {
    final clamped = count.clamp(1, 12);
    while (_playerControllers.length < clamped) {
      _playerControllers.add(TextEditingController());
      _teamControllers.add(TextEditingController());
    }
    while (_playerControllers.length > clamped) {
      _playerControllers.removeLast().dispose();
      _teamControllers.removeLast().dispose();
    }
    for (var r = 0; r < _cellControllers.length; r++) {
      while (_cellControllers[r].length < clamped) {
        _cellControllers[r].add(TextEditingController());
      }
      while (_cellControllers[r].length > clamped) {
        _cellControllers[r].removeLast().dispose();
      }
    }
    _localRefresh();
  }

  void _addRound() {
    final n = _playerControllers.length;
    _roundLabelControllers.add(
      TextEditingController(
        text: 'Tour ${_roundLabelControllers.length + 1}',
      ),
    );
    _cellControllers.add(
      List.generate(n, (_) => TextEditingController()),
    );
    _localRefresh();
  }

  void _removeRound(int index) {
    if (_roundLabelControllers.length <= 1) return;
    _roundLabelControllers.removeAt(index).dispose();
    for (final c in _cellControllers.removeAt(index)) {
      c.dispose();
    }
    _localRefresh();
  }

  Future<void> _pickPlayerForColumn(int index) async {
    if (widget.onPickPlayer == null) return;
    final name = await widget.onPickPlayer!(index);
    if (name == null || !mounted) return;
    _playerControllers[index].text = name;
    _localRefresh();
  }

  @override
  Widget build(BuildContext context) {
    // Force rebuild when typing for totals row.
    // ignore: unused_local_variable
    final _ = _revision;

    final scheme = Theme.of(context).colorScheme;
    final grid = buildGrid();
    final totals = grid.columnTotals();
    final teamTotals = grid.teamTotals();
    final winners = grid.winningColumnIndices(widget.winCondition);
    final colCount = _playerControllers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.enabled) ...[
          Row(
            children: [
              Text(
                'Joueurs',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Retirer une colonne',
                onPressed: colCount > 1
                    ? () => _setColumnCount(colCount - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline, size: 20),
              ),
              Text('$colCount', style: const TextStyle(fontSize: 13)),
              IconButton(
                tooltip: 'Ajouter une colonne',
                onPressed: colCount < 12
                    ? () => _setColumnCount(colCount + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline, size: 20),
              ),
            ],
          ),
          if (widget.onTeamsChanged != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Équipes'),
              subtitle: const Text('Regrouper les joueurs par équipe'),
              value: widget.useTeams,
              onChanged: widget.onTeamsChanged,
            ),
        ],
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(80),
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                verticalInside: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              children: [
                if (widget.useTeams)
                  TableRow(
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer.withValues(alpha: 0.35),
                    ),
                    children: [
                      _staticCell('Équipe', minHeight: 36),
                      ...List.generate(
                        colCount,
                        (i) => _teamCell(i, scheme),
                      ),
                    ],
                  ),
                TableRow(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.45),
                  ),
                  children: [
                    _cornerCell('Tours'),
                    ...List.generate(
                      colCount,
                      (i) => _playerCell(i, scheme, winners.contains(i)),
                    ),
                  ],
                ),
                ...List.generate(_roundLabelControllers.length, (r) {
                  return TableRow(
                    children: [
                      _roundLabelCell(r, scheme),
                      ...List.generate(
                        colCount,
                        (c) => _scoreCell(r, c, scheme, winners.contains(c)),
                      ),
                    ],
                  );
                }),
                TableRow(
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: 0.55),
                  ),
                  children: [
                    _staticCell(
                      widget.winCondition == BoardgameWinCondition.cooperative
                          ? 'Score équipe'
                          : 'Total',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    ...List.generate(colCount, (i) {
                      final hasName = i < _playerControllers.length &&
                          _playerControllers[i].text.trim().isNotEmpty;
                      String text = '—';
                      if (hasName && grid.hasScores) {
                        if (widget.useTeams &&
                            widget.winCondition !=
                                BoardgameWinCondition.cooperative) {
                          final team = i < _teamControllers.length
                              ? _teamControllers[i].text.trim()
                              : '';
                          if (team.isNotEmpty) {
                            text = '${teamTotals[team] ?? 0}';
                          } else {
                            text = '${i < totals.length ? totals[i] : 0}';
                          }
                        } else {
                          text = '${i < totals.length ? totals[i] : 0}';
                        }
                      }
                      final isWinner = winners.contains(i) &&
                          widget.winCondition !=
                              BoardgameWinCondition.cooperative;
                      return _staticCell(
                        text,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isWinner
                              ? scheme.primary
                              : scheme.onSecondaryContainer,
                        ),
                        trailing: isWinner
                            ? Icon(
                                Icons.emoji_events,
                                size: 14,
                                color: scheme.primary,
                              )
                            : null,
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (widget.enabled) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: _addRound,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tour'),
              ),
              if (_roundLabelControllers.length > 1)
                TextButton.icon(
                  onPressed: () =>
                      _removeRound(_roundLabelControllers.length - 1),
                  icon: const Icon(Icons.remove, size: 18),
                  label: const Text('Retirer'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _cornerCell(String text) => _staticCell(text, minHeight: 44);

  Widget _staticCell(
    String text, {
    TextStyle? style,
    double minHeight = 40,
    Widget? trailing,
  }) {
    return SizedBox(
      height: minHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: style ??
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 2),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamCell(int index, ColorScheme scheme) {
    if (!widget.enabled) {
      return _staticCell(
        index < _teamControllers.length ? _teamControllers[index].text : '',
      );
    }
    return Padding(
      padding: const EdgeInsets.all(3),
      child: TextField(
        key: ValueKey('team_$index'),
        controller: _teamControllers[index],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'A',
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        ),
        onChanged: (_) => _localRefresh(),
      ),
    );
  }

  Widget _playerCell(int index, ColorScheme scheme, bool isWinner) {
    if (!widget.enabled) {
      return _staticCell(
        index < _playerControllers.length
            ? _playerControllers[index].text
            : '',
        trailing: isWinner
            ? Icon(Icons.emoji_events, size: 14, color: scheme.primary)
            : null,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          if (widget.onPickPlayer != null)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Choisir un joueur',
              onPressed: () => _pickPlayerForColumn(index),
              icon: Icon(Icons.person_search, size: 16, color: scheme.primary),
            ),
          Expanded(
            child: TextField(
              key: ValueKey('player_$index'),
              controller: _playerControllers[index],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isWinner ? scheme.primary : null,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'J${index + 1}',
                filled: true,
                fillColor: isWinner
                    ? scheme.primaryContainer.withValues(alpha: 0.5)
                    : scheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                suffixIcon: isWinner
                    ? Icon(Icons.emoji_events, size: 14, color: scheme.primary)
                    : null,
              ),
              onChanged: (_) => _localRefresh(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundLabelCell(int row, ColorScheme scheme) {
    if (!widget.enabled) {
      return _staticCell(_roundLabelControllers[row].text);
    }
    return Padding(
      padding: const EdgeInsets.all(4),
      child: TextField(
        key: ValueKey('round_$row'),
        controller: _roundLabelControllers[row],
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'T${row + 1}',
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        onChanged: (_) => _localRefresh(),
      ),
    );
  }

  Widget _scoreCell(int row, int col, ColorScheme scheme, bool isWinnerCol) {
    if (!widget.enabled) {
      return _staticCell(_cellControllers[row][col].text);
    }
    return Padding(
      padding: const EdgeInsets.all(4),
      child: TextField(
        key: ValueKey('cell_${row}_$col'),
        controller: _cellControllers[row][col],
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))],
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isWinnerCol ? scheme.primary : null,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: '·',
          filled: true,
          fillColor: isWinnerCol
              ? scheme.primaryContainer.withValues(alpha: 0.25)
              : scheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: (_) => _localRefresh(),
      ),
    );
  }
}
