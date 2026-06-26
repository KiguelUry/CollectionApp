import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/boardgame_score_grid.dart';

/// Palette de 20 couleurs contrastées pour colonnes joueur / équipe.
const List<Color> kBoardgameColumnPalette = [
  Color(0xFFE57373),
  Color(0xFF64B5F6),
  Color(0xFF81C784),
  Color(0xFFFFB74D),
  Color(0xFFBA68C8),
  Color(0xFF4DD0E1),
  Color(0xFFA1887F),
  Color(0xFF9575CD),
  Color(0xFF4DB6AC),
  Color(0xFFFF8A65),
  Color(0xFF7986CB),
  Color(0xFFAED581),
  Color(0xFFFFD54F),
  Color(0xFFF06292),
  Color(0xFF4FC3F7),
  Color(0xFFDCE775),
  Color(0xFFFF8A80),
  Color(0xFF80CBC4),
  Color(0xFFCE93D8),
  Color(0xFFFFCC80),
];

/// Éditeur grille + gestionnaire de joueurs externe.
class BoardgameScoreGridEditor extends StatefulWidget {
  final BoardgameScoreGrid initialGrid;
  final bool enabled;
  final bool useTeams;
  final BoardgameWinCondition winCondition;
  final ValueChanged<bool>? onTeamsChanged;
  final Future<String?> Function()? onPickPlayer;
  final bool showScoreTable;
  final List<String> suggestedPlayerNames;

  const BoardgameScoreGridEditor({
    super.key,
    required this.initialGrid,
    this.enabled = true,
    this.useTeams = false,
    this.winCondition = BoardgameWinCondition.highest,
    this.onTeamsChanged,
    this.onPickPlayer,
    this.showScoreTable = true,
    this.suggestedPlayerNames = const [],
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
  late List<int?> _playerColorIndices;
  late List<TextEditingController> _definedTeamControllers;
  final Map<String, int> _teamColorIndices = {};
  late TeamScoreMode _teamScoreMode;
  final _newPlayerController = TextEditingController();
  final _newTeamController = TextEditingController();
  final _newDefinedTeamController = TextEditingController();
  int? _newPlayerColorIndex;
  late int _revision;
  bool _hideTotals = false;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.initialGrid);
  }

  @override
  void didUpdateWidget(BoardgameScoreGridEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Conserver équipes / couleurs en mémoire — pas de reset destructif.
  }

  @override
  void dispose() {
    _newPlayerController.dispose();
    _newTeamController.dispose();
    _newDefinedTeamController.dispose();
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
    _playerColorIndices = grid.playerColors.length == grid.players.length
        ? List<int?>.from(grid.playerColors)
        : List<int?>.filled(grid.players.length, null);
    _teamScoreMode = grid.teamScoreMode;
    _definedTeamControllers = grid.uniqueTeamNames()
        .map((n) => TextEditingController(text: n))
        .toList();
    _teamColorIndices.clear();
    _teamColorIndices.addAll(grid.teamColorMap);
    for (var i = 0; i < _teamControllers.length; i++) {
      final team = _teamControllers[i].text.trim();
      final ci = _playerColorIndices[i];
      if (team.isNotEmpty && ci != null) {
        _teamColorIndices.putIfAbsent(team, () => ci);
      }
    }
    for (final c in _definedTeamControllers) {
      final name = c.text.trim();
      if (name.isNotEmpty && !_teamColorIndices.containsKey(name)) {
        _teamColorIndices[name] = _pickNextColorIndex();
      }
    }
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
    for (final c in _definedTeamControllers) {
      c.dispose();
    }
  }

  int _pickNextColorIndex() {
    final used = <int>{
      ..._playerColorIndices.whereType<int>(),
      ..._teamColorIndices.values,
    };
    for (var i = 0; i < kBoardgameColumnPalette.length; i++) {
      if (!used.contains(i)) return i;
    }
    return Random().nextInt(kBoardgameColumnPalette.length);
  }

  Color _colorForColumn(int index) {
    if (widget.useTeams) {
      final team = index < _teamControllers.length
          ? _teamControllers[index].text.trim()
          : '';
      if (team.isNotEmpty) {
        final ci = _teamColorIndices[team];
        if (ci != null && ci >= 0 && ci < kBoardgameColumnPalette.length) {
          return kBoardgameColumnPalette[ci];
        }
      }
    }
    final ci = index < _playerColorIndices.length
        ? _playerColorIndices[index]
        : null;
    if (ci != null && ci >= 0 && ci < kBoardgameColumnPalette.length) {
      return kBoardgameColumnPalette[ci];
    }
    return kBoardgameColumnPalette[index % kBoardgameColumnPalette.length];
  }

  void _applyTeamColor(String team, int colorIndex) {
    _teamColorIndices[team] = colorIndex;
    for (var i = 0; i < _teamControllers.length; i++) {
      if (_teamControllers[i].text.trim() == team) {
        _playerColorIndices[i] = colorIndex;
      }
    }
  }

  String? get _selectedTeamForColor {
    if (!widget.useTeams) return null;
    final fromDropdown = _newTeamController.text.trim();
    if (fromDropdown.isNotEmpty) return fromDropdown;
    return null;
  }

  bool _isColorAvailable(int i) {
    if (widget.useTeams) {
      final team = _selectedTeamForColor;
      if (team != null && _teamColorIndices[team] == i) return true;
      return !_teamColorIndices.values.contains(i);
    }
    final usedByPlayers = _playerColorIndices.whereType<int>().toSet();
    return !usedByPlayers.contains(i) || _newPlayerColorIndex == i;
  }

  void _deferRefresh(void Function() fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fn();
      _localRefresh();
    });
  }

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
    return BoardgameScoreGrid(
      players: players,
      rounds: rounds,
      teams: teams,
      playerColors: List<int?>.from(_playerColorIndices),
      teamColorMap: Map<String, int>.from(_teamColorIndices),
      teamScoreMode: _teamScoreMode,
    );
  }

  void _localRefresh() => setState(() => _revision++);

  bool get _hasTableContent {
    if (_playerControllers.any((c) => c.text.trim().isNotEmpty)) return true;
    return _playerControllers.isNotEmpty;
  }

  void _addPlayerColumn({String? name, String? team, int? colorIndex}) {
    var ci = colorIndex ?? _pickNextColorIndex();
    if (widget.useTeams && team != null && team.isNotEmpty) {
      ci = _teamColorIndices[team] ?? colorIndex ?? _pickNextColorIndex();
      _teamColorIndices[team] = ci;
    }
    _playerControllers.add(TextEditingController(text: name ?? ''));
    _teamControllers.add(TextEditingController(text: team ?? ''));
    _playerColorIndices.add(ci);
    for (var r = 0; r < _cellControllers.length; r++) {
      _cellControllers[r].add(TextEditingController());
    }
    if (_roundLabelControllers.isEmpty) {
      _addRound();
    }
    if (widget.useTeams) _sortColumnsByTeam();
    _localRefresh();
  }

  void _reorderColumns(List<int> order) {
    if (order.length != _playerControllers.length) return;
    _playerControllers = order.map((i) => _playerControllers[i]).toList();
    _teamControllers = order.map((i) => _teamControllers[i]).toList();
    _playerColorIndices = order.map((i) => _playerColorIndices[i]).toList();
    for (var r = 0; r < _cellControllers.length; r++) {
      _cellControllers[r] = order.map((i) => _cellControllers[r][i]).toList();
    }
  }

  void _sortColumnsByTeam() {
    if (!widget.useTeams || _playerControllers.isEmpty) return;
    final order = List.generate(_playerControllers.length, (i) => i);
    order.sort((a, b) {
      final ta = _teamControllers[a].text.trim();
      final tb = _teamControllers[b].text.trim();
      if (ta.isEmpty && tb.isEmpty) {
        return _playerControllers[a].text
            .trim()
            .toLowerCase()
            .compareTo(_playerControllers[b].text.trim().toLowerCase());
      }
      if (ta.isEmpty) return 1;
      if (tb.isEmpty) return -1;
      final cmp = ta.toLowerCase().compareTo(tb.toLowerCase());
      if (cmp != 0) return cmp;
      return _playerControllers[a].text
          .trim()
          .toLowerCase()
          .compareTo(_playerControllers[b].text.trim().toLowerCase());
    });
    _reorderColumns(order);
  }

  List<String> get _availableSuggestions {
    final atTable = _playerControllers
        .map((c) => c.text.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    return widget.suggestedPlayerNames
        .where((n) => !atTable.contains(n.toLowerCase()))
        .toList();
  }

  void _addSuggestedPlayer(String name) {
    final team = widget.useTeams ? _newTeamController.text.trim() : '';
    _addPlayerColumn(
      name: name,
      team: team.isEmpty ? null : team,
      colorIndex: _newPlayerColorIndex,
    );
  }

  void _removePlayer(int index) {
    if (index < 0 || index >= _playerControllers.length) return;
    _playerControllers.removeAt(index).dispose();
    _teamControllers.removeAt(index).dispose();
    _playerColorIndices.removeAt(index);
    for (final row in _cellControllers) {
      row.removeAt(index).dispose();
    }
    _localRefresh();
  }

  void _addRound() {
    final n = _playerControllers.length;
    final idx = _roundLabelControllers.length;
    _roundLabelControllers.add(
      TextEditingController(text: 'Tour ${idx + 1}'),
    );
    _cellControllers.add(List.generate(n, (_) => TextEditingController()));
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

  void _addDefinedTeam() {
    final name = _newDefinedTeamController.text.trim();
    if (name.isEmpty) return;
    if (_definedTeamControllers.any((c) => c.text.trim() == name)) return;
    _definedTeamControllers.add(TextEditingController(text: name));
    _teamColorIndices.putIfAbsent(name, _pickNextColorIndex);
    _newDefinedTeamController.clear();
    _localRefresh();
  }

  void _removeDefinedTeam(int index) {
    final removed = _definedTeamControllers.removeAt(index).text.trim();
    _teamColorIndices.remove(removed);
    for (final c in _teamControllers) {
      if (c.text.trim() == removed) c.clear();
    }
    _localRefresh();
  }

  void _addFromFields() {
    final name = _newPlayerController.text.trim();
    if (name.isEmpty) return;
    final team = widget.useTeams ? _newTeamController.text.trim() : '';
    _addPlayerColumn(
      name: name,
      team: team.isEmpty ? null : team,
      colorIndex: _newPlayerColorIndex,
    );
    _newPlayerController.clear();
    if (widget.useTeams) {
      // Conserver l'équipe sélectionnée pour enchaîner les ajouts.
      _newPlayerColorIndex = team.isNotEmpty ? _teamColorIndices[team] : null;
    } else {
      _newTeamController.clear();
      _newPlayerColorIndex = null;
    }
  }

  Future<void> _editPlayer(int index) async {
    final nameCtrl =
        TextEditingController(text: _playerControllers[index].text);
    final teamCtrl = TextEditingController(text: _teamControllers[index].text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le joueur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Prénom'),
            ),
            if (widget.useTeams) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue:
                    teamCtrl.text.trim().isEmpty ? null : teamCtrl.text.trim(),
                decoration: const InputDecoration(labelText: 'Équipe'),
                items: [
                  for (final c in _definedTeamControllers)
                    if (c.text.trim().isNotEmpty)
                      DropdownMenuItem(
                        value: c.text.trim(),
                        child: Text(c.text.trim()),
                      ),
                  if (teamCtrl.text.trim().isNotEmpty &&
                      !_definedTeamControllers
                          .any((c) => c.text.trim() == teamCtrl.text.trim()))
                    DropdownMenuItem(
                      value: teamCtrl.text.trim(),
                      child: Text(teamCtrl.text.trim()),
                    ),
                ],
                onChanged: (v) => teamCtrl.text = v ?? '',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final name = nameCtrl.text;
      final team = teamCtrl.text.trim();
      _deferRefresh(() {
        _playerControllers[index].text = name;
        if (widget.useTeams) {
          _teamControllers[index].text = team;
          if (team.isNotEmpty) {
            final ci = _teamColorIndices[team] ?? _pickNextColorIndex();
            _applyTeamColor(team, ci);
          }
          _sortColumnsByTeam();
        }
      });
    }
    nameCtrl.dispose();
    teamCtrl.dispose();
  }

  void _shuffleRoster() {
    final rng = Random();
    if (widget.useTeams && _definedTeamControllers.isNotEmpty) {
      final labels = _definedTeamControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList()
        ..sort();
      if (labels.isEmpty) return;
      final n = _teamControllers.length;
      final k = labels.length;
      final base = n ~/ k;
      final extra = n % k;
      final slots = <String>[];
      for (var i = 0; i < k; i++) {
        final count = base + (i < extra ? 1 : 0);
        slots.addAll(List.filled(count, labels[i]));
      }
      slots.shuffle(rng);
      for (var i = 0; i < n; i++) {
        final team = slots[i];
        _teamControllers[i].text = team;
        final ci = _teamColorIndices[team];
        if (ci != null) _playerColorIndices[i] = ci;
      }
      _sortColumnsByTeam();
    } else if (widget.useTeams) {
      final labels = ['A', 'B', 'C', 'D', 'E', 'F'];
      for (var i = 0; i < _teamControllers.length; i++) {
        _teamControllers[i].text = labels[rng.nextInt(labels.length)];
      }
    } else {
      final names = _playerControllers.map((c) => c.text).toList();
      names.shuffle(rng);
      for (var i = 0; i < names.length; i++) {
        _playerControllers[i].text = names[i];
      }
    }
    _localRefresh();
  }

  void _selectColor(int i) {
    if (widget.useTeams) {
      final team = _selectedTeamForColor;
      if (team == null) return;
      _applyTeamColor(team, i);
      _newPlayerColorIndex = i;
    } else {
      _newPlayerColorIndex = i;
    }
    _localRefresh();
  }

  double _measureTextWidth(String text, {double fontSize = 12}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  double _colWidth(int index) {
    final name = _playerControllers[index].text.trim();
    final team = widget.useTeams ? _teamControllers[index].text.trim() : '';
    final w = max(
      _measureTextWidth(name.isEmpty ? 'Joueur' : name, fontSize: 12),
      team.isEmpty ? 0.0 : _measureTextWidth(team, fontSize: 10),
    );
    return (w + 28).clamp(72.0, 220.0);
  }

  double _labelColWidth() {
    var maxWordW = _measureTextWidth('Joueurs', fontSize: 11);
    var maxLines = 1;
    for (final label in ['Équipes', 'Joueurs', 'Total', 'Score']) {
      maxWordW = max(maxWordW, _measureTextWidth(label, fontSize: 11));
    }
    for (final c in _roundLabelControllers) {
      final text = c.text.trim().isEmpty ? 'Tour' : c.text.trim();
      final words = text.split(RegExp(r'\s+'));
      maxLines = max(maxLines, words.length);
      for (final w in words) {
        maxWordW = max(maxWordW, _measureTextWidth(w, fontSize: 11));
      }
    }
    return maxWordW.clamp(56.0, 200.0) + 16;
  }

  Widget _multiWordLabel(String text, {TextStyle? style}) {
    final words = text.trim().split(RegExp(r'\s+'));
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: words
          .map(
            (w) => Text(
              w,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: style,
            ),
          )
          .toList(),
    );
  }

  List<({int start, int span, String team, double width})> _teamSpans() {
    final spans = <({int start, int span, String team, double width})>[];
    final colCount = _playerControllers.length;
    var i = 0;
    while (i < colCount) {
      final team = _teamControllers[i].text.trim();
      var span = 1;
      var width = _colWidth(i);
      while (i + span < colCount &&
          _teamControllers[i + span].text.trim() == team) {
        width += _colWidth(i + span);
        span++;
      }
      spans.add((start: i, span: span, team: team, width: width));
      i += span;
    }
    return spans;
  }

  Widget _singleLineText(
    String text, {
    TextStyle? style,
    TextAlign align = TextAlign.center,
  }) {
    return Text(
      text,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: style,
    );
  }

  Widget _stretchRow(List<Widget> children) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _ = _revision;

    final scheme = Theme.of(context).colorScheme;
    final grid = buildGrid();
    final totals = grid.columnTotals();
    final teamTotals = grid.teamTotals();
    final winners = grid.winningColumnIndices(widget.winCondition);
    final colCount = _playerControllers.length;
    final labelW = _labelColWidth();
    final sharedTeams = widget.useTeams &&
        _teamScoreMode == TeamScoreMode.shared &&
        colCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.enabled) ...[
          // ── Bloc 1 : toggle équipes ──
          if (widget.onTeamsChanged != null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Équipes'),
              value: widget.useTeams,
              onChanged: (v) => widget.onTeamsChanged!(v),
            ),
            const SizedBox(height: 16),
          ],

          // ── Bloc 2 : configuration des équipes ──
          if (widget.useTeams) ...[
            Text(
              'Configuration des équipes',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newDefinedTeamController,
                    decoration: const InputDecoration(
                      hintText: 'Nom d\'équipe',
                    ),
                    onSubmitted: (_) => _addDefinedTeam(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addDefinedTeam,
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Ajouter équipe',
                ),
              ],
            ),
            if (_definedTeamControllers.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_definedTeamControllers.length, (i) {
                  final name = _definedTeamControllers[i].text.trim();
                  final ci = _teamColorIndices[name];
                  return InputChip(
                    avatar: CircleAvatar(
                      radius: 10,
                      backgroundColor: ci != null
                          ? kBoardgameColumnPalette[ci]
                          : scheme.surfaceContainerHighest,
                    ),
                    label: Text(name),
                    onPressed: widget.enabled
                        ? () {
                            setState(() {
                              _newTeamController.text = name;
                              _newPlayerColorIndex = ci;
                            });
                          }
                        : null,
                    onDeleted: () => _removeDefinedTeam(i),
                  );
                }),
              ),
            ],
            const SizedBox(height: 10),
            SegmentedButton<TeamScoreMode>(
              segments: const [
                ButtonSegment(
                  value: TeamScoreMode.divided,
                  label: Text('Par joueur'),
                ),
                ButtonSegment(
                  value: TeamScoreMode.shared,
                  label: Text('Commun'),
                ),
              ],
              selected: {_teamScoreMode},
              onSelectionChanged: (s) =>
                  setState(() => _teamScoreMode = s.first),
            ),
            const SizedBox(height: 20),
          ],

          // ── Bloc 3 : ajout de joueurs ──
          Text(
            'Joueurs à la table',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _newPlayerController,
            decoration: const InputDecoration(
              hintText: 'Prénom',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addFromFields(),
          ),
          if (_availableSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _availableSuggestions.map((name) {
                return ActionChip(
                  label: Text(name),
                  onPressed: () => _addSuggestedPlayer(name),
                );
              }).toList(),
            ),
          ],
          if (widget.useTeams) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _newTeamController.text.trim().isEmpty
                  ? null
                  : _newTeamController.text.trim(),
              decoration: const InputDecoration(labelText: 'Équipe'),
              items: [
                for (final c in _definedTeamControllers)
                  if (c.text.trim().isNotEmpty)
                    DropdownMenuItem(
                      value: c.text.trim(),
                      child: Text(c.text.trim()),
                    ),
              ],
              onChanged: (v) {
                _newTeamController.text = v ?? '';
                if (v != null && _teamColorIndices.containsKey(v)) {
                  _newPlayerColorIndex = _teamColorIndices[v];
                }
                _localRefresh();
              },
            ),
          ],
          const SizedBox(height: 12),
          Text(
            widget.useTeams ? 'Couleur de l\'équipe' : 'Couleur du joueur',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kBoardgameColumnPalette.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final selected = widget.useTeams
                    ? _teamColorIndices[_selectedTeamForColor ?? ''] == i
                    : _newPlayerColorIndex == i;
                final available = _isColorAvailable(i);
                return GestureDetector(
                  onTap: available ? () => _selectColor(i) : null,
                  child: Opacity(
                    opacity: available ? 1 : 0.25,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: kBoardgameColumnPalette[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? scheme.onSurface
                              : scheme.outlineVariant.withValues(alpha: 0.4),
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: _addFromFields,
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Ajouter'),
              ),
              if (widget.onPickPlayer != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () async {
                    final name = await widget.onPickPlayer!();
                    if (name != null && name.trim().isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _addPlayerColumn(
                          name: name.trim(),
                          team: widget.useTeams &&
                                  _newTeamController.text.trim().isNotEmpty
                              ? _newTeamController.text.trim()
                              : null,
                        );
                      });
                    }
                  },
                  icon: const Icon(Icons.person_search_outlined),
                  tooltip: 'Depuis mes contacts',
                ),
              ],
              IconButton(
                onPressed: _shuffleRoster,
                icon: const Icon(Icons.shuffle),
                tooltip: 'Mélanger',
              ),
            ],
          ),

          // ── Bloc 4 : badges joueurs ──
          if (_playerControllers.any((c) => c.text.trim().isNotEmpty)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < colCount; i++)
                  if (_playerControllers[i].text.trim().isNotEmpty)
                    InputChip(
                      avatar: CircleAvatar(
                        radius: 10,
                        backgroundColor: _colorForColumn(i),
                      ),
                      label: Text(
                        widget.useTeams &&
                                _teamControllers[i].text.trim().isNotEmpty
                            ? '${_playerControllers[i].text.trim()} (${_teamControllers[i].text.trim()})'
                            : _playerControllers[i].text.trim(),
                        style: const TextStyle(fontSize: 13),
                      ),
                      onPressed: widget.enabled ? () => _editPlayer(i) : null,
                      onDeleted:
                          widget.enabled ? () => _removePlayer(i) : null,
                    ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],

        // ── Bloc 5 : grille de score ──
        if (widget.showScoreTable && _hasTableContent) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Grille de score',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (widget.enabled)
                IconButton(
                  onPressed: () => setState(() => _hideTotals = !_hideTotals),
                  icon: Icon(
                    _hideTotals
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  tooltip: _hideTotals
                      ? 'Afficher les totaux'
                      : 'Masquer les totaux (anti-spoil)',
                ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.useTeams && !sharedTeams && colCount > 0)
                    _stretchRow([
                      _cornerLabel('Équipes', labelW, scheme,
                          bg: scheme.tertiaryContainer
                              .withValues(alpha: 0.35)),
                      ..._teamSpans().map(
                        (s) {
                          final ci = s.team.isNotEmpty
                              ? _teamColorIndices[s.team]
                              : null;
                          final teamBg = ci != null
                              ? kBoardgameColumnPalette[ci]
                                  .withValues(alpha: 0.35)
                              : scheme.tertiaryContainer
                                  .withValues(alpha: 0.35);
                          return Container(
                            width: s.width,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 10,
                            ),
                            color: teamBg,
                            child: _singleLineText(
                              s.team.isEmpty ? '—' : s.team,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                          );
                        },
                      ),
                    ]),
                  if (widget.useTeams && !sharedTeams && colCount > 0)
                    Container(
                      height: 2,
                      color: scheme.outline.withValues(alpha: 0.45),
                    ),
                  if (colCount > 0)
                    _stretchRow([
                      _cornerLabel('Joueurs', labelW, scheme,
                          bg: scheme.primaryContainer
                              .withValues(alpha: 0.25)),
                      if (sharedTeams)
                        ...grid.uniqueTeamNames().map((team) {
                          final indices = grid.indicesForTeam(team);
                          if (indices.isEmpty) return const SizedBox.shrink();
                          final w = indices.fold<double>(
                            0,
                            (a, i) => a + _colWidth(i),
                          );
                          final names = indices
                              .map((i) => _playerControllers[i].text.trim())
                              .where((n) => n.isNotEmpty)
                              .join(', ');
                          final ci = _teamColorIndices[team];
                          return Container(
                            width: w,
                            padding: const EdgeInsets.all(6),
                            color: ci != null
                                ? kBoardgameColumnPalette[ci]
                                    .withValues(alpha: 0.35)
                                : scheme.primaryContainer
                                    .withValues(alpha: 0.25),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _singleLineText(
                                  team,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                                if (names.isNotEmpty)
                                  _singleLineText(
                                    names,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        })
                      else
                        ...List.generate(
                          colCount,
                          (i) => _playerHeaderCell(i, scheme, _colWidth(i)),
                        ),
                    ]),
                  for (var r = 0; r < _roundLabelControllers.length; r++)
                    _stretchRow([
                      _roundLabelCell(r, scheme, labelW),
                      if (sharedTeams)
                        ...grid.uniqueTeamNames().map((team) {
                          final indices = grid.indicesForTeam(team);
                          if (indices.isEmpty) return const SizedBox.shrink();
                          final lead = indices.first;
                          final w = indices.fold<double>(
                            0,
                            (a, i) => a + _colWidth(i),
                          );
                          return _scoreCell(
                            r,
                            lead,
                            scheme,
                            w,
                            syncIndices: indices,
                          );
                        })
                      else
                        ...List.generate(
                          colCount,
                          (c) => _scoreCell(r, c, scheme, _colWidth(c)),
                        ),
                    ]),
                  if (widget.useTeams &&
                      _teamScoreMode == TeamScoreMode.divided &&
                      !sharedTeams &&
                      colCount > 0)
                    _teamTotalRow(grid, teamTotals, labelW, scheme),
                  if (colCount > 0)
                    _stretchRow([
                      _cornerLabel(
                        widget.winCondition ==
                                BoardgameWinCondition.cooperative
                            ? 'Score'
                            : 'Total',
                        labelW,
                        scheme,
                        bg: scheme.secondaryContainer.withValues(alpha: 0.55),
                        bold: true,
                      ),
                      if (sharedTeams)
                        ...grid.uniqueTeamNames().map((team) {
                          final indices = grid.indicesForTeam(team);
                          if (indices.isEmpty) return const SizedBox.shrink();
                          final w = indices.fold<double>(
                            0,
                            (a, i) => a + _colWidth(i),
                          );
                          final total = teamTotals[team] ?? 0;
                          final isWinner = !_hideTotals &&
                              indices.any(winners.contains) &&
                              widget.winCondition !=
                                  BoardgameWinCondition.cooperative;
                          return _totalCell(
                            _hideTotals ? '?' : '$total',
                            w,
                            scheme,
                            isWinner: isWinner,
                          );
                        })
                      else
                        ...List.generate(colCount, (i) {
                          final hasName =
                              _playerControllers[i].text.trim().isNotEmpty;
                          String text = '—';
                          if (_hideTotals && hasName && grid.hasScores) {
                            text = '?';
                          } else if (hasName && grid.hasScores) {
                            if (widget.useTeams &&
                                widget.winCondition !=
                                    BoardgameWinCondition.cooperative) {
                              final team = _teamControllers[i].text.trim();
                              text = team.isNotEmpty
                                  ? '${teamTotals[team] ?? 0}'
                                  : '${i < totals.length ? totals[i] : 0}';
                            } else {
                              text = '${i < totals.length ? totals[i] : 0}';
                            }
                          }
                          final isWinner = !_hideTotals &&
                              winners.contains(i) &&
                              widget.winCondition !=
                                  BoardgameWinCondition.cooperative;
                          return _totalCell(
                            text,
                            _colWidth(i),
                            scheme,
                            isWinner: isWinner,
                          );
                        }),
                    ]),
                ],
              ),
            ),
          ),
          if (widget.enabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _addRound,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ligne'),
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
      ],
    );
  }

  Widget _cornerLabel(
    String text,
    double width,
    ColorScheme scheme, {
    Color? bg,
    bool bold = false,
  }) {
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      color: bg,
      child: _multiWordLabel(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget _playerHeaderCell(int index, ColorScheme scheme, double width) {
    final raw = _playerControllers[index].text.trim();
    final color = _colorForColumn(index);
    return Container(
      width: width,
      padding: const EdgeInsets.all(6),
      color: color.withValues(alpha: 0.35),
      child: _singleLineText(
        raw.isEmpty ? '—' : raw,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _roundLabelCell(int row, ColorScheme scheme, double width) {
    if (!widget.enabled) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: _multiWordLabel(
            _roundLabelControllers[row].text,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      );
    }
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: TextField(
          key: ValueKey('round_$row'),
          controller: _roundLabelControllers[row],
          style: const TextStyle(fontSize: 11),
          minLines: 1,
          maxLines: 1,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tour ${row + 1}',
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          onChanged: (_) => _localRefresh(),
        ),
      ),
    );
  }

  Widget _scoreCell(
    int row,
    int col,
    ColorScheme scheme,
    double width, {
    List<int>? syncIndices,
  }) {
    final color = _colorForColumn(col).withValues(alpha: 0.12);
    if (!widget.enabled) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: _singleLineText(_cellControllers[row][col].text),
        ),
      );
    }
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: TextField(
          key: ValueKey('cell_${row}_$col'),
          controller: _cellControllers[row][col],
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
          ],
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            hintText: '·',
            filled: true,
            fillColor: color,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (v) {
            if (syncIndices != null) {
              for (final i in syncIndices) {
                if (i != col) _cellControllers[row][i].text = v;
              }
            }
            _localRefresh();
          },
        ),
      ),
    );
  }

  Widget _totalCell(
    String text,
    double width,
    ColorScheme scheme, {
    required bool isWinner,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      color: scheme.secondaryContainer.withValues(alpha: 0.55),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isWinner
                    ? scheme.primary
                    : scheme.onSecondaryContainer,
              ),
            ),
          ),
          if (isWinner) ...[
            const SizedBox(width: 2),
            Icon(Icons.emoji_events, size: 16, color: scheme.primary),
          ],
        ],
      ),
    );
  }

  Widget _teamTotalRow(
    BoardgameScoreGrid grid,
    Map<String, int> teamTotals,
    double labelW,
    ColorScheme scheme,
  ) {
    return _stretchRow([
      _cornerLabel(
        'Éq.',
        labelW,
        scheme,
        bg: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      ..._teamSpans().map((s) {
        final total = s.team.isEmpty ? '—' : '${teamTotals[s.team] ?? 0}';
        return Container(
          width: s.width,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Text(
            total,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        );
      }),
    ]);
  }
}
