import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/boardgame_play_session.dart';
import '../models/boardgame_score_grid.dart';
import '../models/collection_item.dart';
import '../models/friend_choice.dart';
import '../services/friend_service.dart';
import '../services/play_share_service.dart';
import '../services/player_alias_service.dart';
import '../services/profile_cache_service.dart';
import '../utils/boardgame_past_players.dart';
import '../utils/play_share.dart';
import 'bgg_network_image.dart';
import 'boardgame_ranking_panel.dart';
import 'boardgame_score_grid_editor.dart';

enum BoardgamePlayPanelMode { all, history, ranking }

/// Historique des parties jouées (stocké dans metadata.boardgame_plays).
class BoardgamePlayHistoryPanel extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;
  final BoardgamePlayPanelMode mode;

  const BoardgamePlayHistoryPanel({
    super.key,
    required this.item,
    required this.readOnly,
    required this.onMetadataChanged,
    this.mode = BoardgamePlayPanelMode.all,
  });

  @override
  State<BoardgamePlayHistoryPanel> createState() =>
      _BoardgamePlayHistoryPanelState();
}

class _BoardgamePlayHistoryPanelState extends State<BoardgamePlayHistoryPanel> {
  static const _visibleLimit = 5;
  bool _showAll = false;
  int _tabIndex = 0;

  List<BoardgamePlaySession> get _sessions =>
      parseBoardgamePlays(widget.item.metadata);

  Future<void> _openSessionAtIndex(int index) async {
    if (index < 0 || index >= _sessions.length) return;
    await _openSessionDetail(_sessions[index], index);
  }

  Future<void> _openAddSession({BoardgamePlaySession? prefillFrom}) async {
    final session = await Navigator.push<BoardgamePlaySession>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardgamePlaySessionPage(
          item: widget.item,
          // Prefill roster only — new session (no initial = create).
          template: prefillFrom,
        ),
        fullscreenDialog: true,
      ),
    );
    if (session == null) return;
    final next = [session, ..._sessions];
    _saveSessions(next);
  }

  Future<void> _openSessionDetail(
    BoardgamePlaySession session,
    int index,
  ) async {
    if (widget.readOnly) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => _SessionDetailSheet(session: session),
      );
      return;
    }
    final edited = await Navigator.push<BoardgamePlaySession>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BoardgamePlaySessionPage(item: widget.item, initial: session),
        fullscreenDialog: true,
      ),
    );
    if (edited == null) return;
    final next = List<BoardgamePlaySession>.from(_sessions);
    if (index < 0 || index >= next.length) return;
    next[index] = edited;
    _saveSessions(next);
  }

  void _saveSessions(List<BoardgamePlaySession> sessions) {
    final meta = Map<String, dynamic>.from(widget.item.metadata ?? {});
    meta['boardgame_plays'] = sessions.map((s) => s.toJson()).toList();
    meta['games_played'] = sessions.length;
    widget.onMetadataChanged(meta);
  }

  Future<void> _deleteSession(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette partie ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final next = List<BoardgamePlaySession>.from(_sessions)..removeAt(index);
    _saveSessions(next);
  }

  bool get _showTabs => widget.mode == BoardgamePlayPanelMode.all;

  bool get _showHistory =>
      widget.mode == BoardgamePlayPanelMode.history ||
      (widget.mode == BoardgamePlayPanelMode.all && _tabIndex == 0);

  bool get _showRanking =>
      widget.mode == BoardgamePlayPanelMode.ranking ||
      (widget.mode == BoardgamePlayPanelMode.all && _tabIndex == 1);

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    final dateFmt = DateFormat('d MMM yyyy', 'fr_FR');
    final scheme = Theme.of(context).colorScheme;
    final visible = _showAll || sessions.length <= _visibleLimit
        ? sessions
        : sessions.take(_visibleLimit).toList();
    final hiddenCount = sessions.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showTabs) ...[
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Historique')),
              ButtonSegment(value: 1, label: Text('Classement')),
            ],
            selected: {_tabIndex},
            onSelectionChanged: (s) => setState(() => _tabIndex = s.first),
          ),
          const SizedBox(height: 12),
        ],
        if (_showHistory) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  sessions.isEmpty
                      ? 'Aucune partie enregistrée'
                      : '${sessions.length} partie${sessions.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!widget.readOnly)
                FilledButton.tonalIcon(
                  onPressed: _openAddSession,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Partie'),
                ),
            ],
          ),
          if (sessions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...List.generate(visible.length, (i) {
              final s = visible[i];
              final realIndex = sessions.indexOf(s);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openSessionDetail(s, realIndex),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: scheme.primaryContainer
                                  .withValues(alpha: 0.7),
                              child: Icon(
                                s.trackScores
                                    ? Icons.grid_on_rounded
                                    : Icons.groups,
                                size: 18,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                            if (s.isInProgress)
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade700,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '…',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      dateFmt.format(s.date),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (s.isInProgress)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'En cours',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (s.summaryLine().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  s.summaryLine(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!widget.readOnly)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _deleteSession(realIndex),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (hiddenCount > 0)
              TextButton.icon(
                onPressed: () => setState(() => _showAll = true),
                icon: const Icon(Icons.expand_more),
                label: Text(
                  'Voir $hiddenCount autre${hiddenCount > 1 ? 's' : ''}',
                ),
              )
            else if (_showAll && sessions.length > _visibleLimit)
              TextButton.icon(
                onPressed: () => setState(() => _showAll = false),
                icon: const Icon(Icons.expand_less),
                label: const Text('Réduire'),
              ),
          ],
        ] else if (_showRanking)
          BoardgameRankingPanel(
            sessions: sessions,
            onOpenSession: widget.readOnly ? null : _openSessionAtIndex,
          ),
      ],
    );
  }
}

class _SessionDetailSheet extends StatelessWidget {
  final BoardgamePlaySession session;

  const _SessionDetailSheet({required this.session});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              dateFmt.format(session.date),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (session.winCondition != BoardgameWinCondition.highest) ...[
              const SizedBox(height: 4),
              Text(
                session.winCondition.label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (session.effectiveWinner?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.emoji_events,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text('Gagnant : ${session.effectiveWinner}'),
                ],
              ),
            ],
            if (session.trackScores && session.scoreGrid != null) ...[
              const SizedBox(height: 16),
              BoardgameScoreGridEditor(
                initialGrid: session.scoreGrid!,
                enabled: false,
                useTeams: session.useTeams,
                winCondition: session.winCondition,
              ),
            ],
            if (session.notes?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(session.notes!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Page complète pour saisir une partie (grille de points incluse).
class BoardgamePlaySessionPage extends StatefulWidget {
  final CollectionItem? item;

  /// Édition d'une partie existante.
  final BoardgamePlaySession? initial;

  /// Préremplissage (relaunch) sans éditer l'ancienne partie.
  final BoardgamePlaySession? template;

  static const maxContentWidth = 850.0;

  const BoardgamePlaySessionPage({
    super.key,
    this.item,
    this.initial,
    this.template,
  });

  @override
  State<BoardgamePlaySessionPage> createState() =>
      _BoardgamePlaySessionPageState();
}

class _BoardgamePlaySessionPageState extends State<BoardgamePlaySessionPage> {
  final _gridKey = GlobalKey<BoardgameScoreGridEditorState>();
  final _friendService = FriendService();
  late DateTime _date;
  late bool _trackScores;
  late bool _useTeams;
  late BoardgameWinCondition _winCondition;
  late BoardgameConfrontationType _confrontation;
  late BoardgamePlayStatus _status;
  late BoardgameScoreGrid _initialGrid;
  bool? _coopVictory;
  int _coopTeamCount = 1;
  final _winnerController = TextEditingController();
  final _notesController = TextEditingController();
  final _playersOnlyController = TextEditingController();
  final _targetScoreController = TextEditingController();
  List<Map<String, dynamic>> _pickableProfiles = [];
  List<FriendChoice> _friendChoices = const [];

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    final t = widget.template;
    final seed = s ?? t;
    _date = s?.date ?? DateTime.now();
    _trackScores = seed?.trackScores ?? false;
    _confrontation =
        seed?.confrontationType ??
        (seed?.useTeams == true
            ? BoardgameConfrontationType.teams
            : BoardgameConfrontationType.freeForAll);
    if (seed?.isCooperative == true) {
      _confrontation = BoardgameConfrontationType.cooperative;
    }
    _useTeams =
        _confrontation == BoardgameConfrontationType.teams ||
        (_confrontation == BoardgameConfrontationType.cooperative &&
            (seed?.coopTeamCount ?? 1) > 1);
    _winCondition = seed?.winCondition == BoardgameWinCondition.cooperative
        ? BoardgameWinCondition.highest
        : (seed?.winCondition ?? BoardgameWinCondition.highest);
    // Nouvelle partie / relaunch → en cours ; édition conserve le statut.
    _status = s?.status ?? BoardgamePlayStatus.inProgress;
    if (s != null && s.scoreGrid != null) {
      _initialGrid = s.scoreGrid!;
    } else if (t?.scoreGrid != null) {
      // Relancer : garder noms/équipes/couleurs, vider les scores.
      final g = t!.scoreGrid!;
      _initialGrid = BoardgameScoreGrid(
        players: List<String>.from(g.players),
        teams: List<String?>.from(g.teams),
        playerColors: List<int?>.from(g.playerColors),
        teamColorMap: Map<String, int>.from(g.teamColorMap),
        teamScoreMode: g.teamScoreMode,
        rounds: [
          BoardgameScoreRound(
            scores: List<int?>.filled(g.players.length, null),
          ),
        ],
      );
    } else {
      _initialGrid = BoardgameScoreGrid.empty(playerCount: 0);
    }
    _winnerController.text = s?.winner ?? '';
    _notesController.text = s?.notes ?? '';
    _playersOnlyController.text = (s ?? t)?.players.join(', ') ?? '';
    _coopVictory = s?.coopVictory;
    _coopTeamCount = seed?.coopTeamCount ?? 1;
    if (seed?.targetScore != null) {
      _targetScoreController.text = '${seed!.targetScore}';
    }
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final me = ProfileCacheService.instance.profile;
    final friends = await _friendService.fetchFriends();
    final list = <Map<String, dynamic>>[];
    if (me != null) {
      list.add({'profile_id': me.id, 'username': me.username});
    }
    list.addAll(friends);
    if (mounted) {
      setState(() {
        _pickableProfiles = list;
        _friendChoices = [
          for (final f in friends)
            FriendChoice(
              profileId: f['profile_id'] as String,
              username: f['username'] as String? ?? 'Ami',
            ),
        ];
      });
    }
  }

  @override
  void dispose() {
    _winnerController.dispose();
    _notesController.dispose();
    _playersOnlyController.dispose();
    _targetScoreController.dispose();
    super.dispose();
  }

  int? get _targetScore => int.tryParse(_targetScoreController.text.trim());

  bool get _isCoop => _confrontation == BoardgameConfrontationType.cooperative;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<String?> _pickPlayerFromContacts() async {
    if (_pickableProfiles.isEmpty) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Choisir un joueur',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (final p in _pickableProfiles)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(p['username'] as String? ?? 'Joueur'),
                  onTap: () =>
                      Navigator.pop(ctx, p['username'] as String? ?? ''),
                ),
            ],
          ),
        );
      },
    );
  }

  void _submit() {
    List<String> players;
    BoardgameScoreGrid? grid;
    Map<String, int>? scores;
    final useTeamsEffective =
        _confrontation == BoardgameConfrontationType.teams ||
        (_isCoop && _coopTeamCount > 1) ||
        _useTeams;

    if (_trackScores && _isCoop && _coopTeamCount <= 1) {
      grid = _gridKey.currentState?.buildGrid() ?? _initialGrid;
      players = grid.activePlayers;
      if (players.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoute au moins un joueur.')),
        );
        return;
      }
      if (_status == BoardgamePlayStatus.finished && _coopVictory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indique victoire ou défaite.')),
        );
        return;
      }
      scores = null;
    } else if (_trackScores) {
      grid = _gridKey.currentState?.buildGrid() ?? _initialGrid;
      players = grid.activePlayers;
      if (players.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Indique au moins un joueur dans la grille.'),
          ),
        );
        return;
      }
      if (_winCondition == BoardgameWinCondition.exactTarget &&
          _targetScore == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indique le score exact à atteindre.')),
        );
        return;
      }
      if (grid.hasScores) scores = grid.toLegacyScores();
    } else {
      players = _playersOnlyController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (players.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indique au moins un joueur.')),
        );
        return;
      }
    }

    final autoNames =
        grid?.winnerNames(_winCondition, targetScore: _targetScore) ??
        const <String>[];
    final manualWinner = _winnerController.text.trim();
    final winner = manualWinner.isNotEmpty
        ? manualWinner
        : (_isCoop ? null : (autoNames.isEmpty ? null : autoNames.join(' & ')));

    final session = BoardgamePlaySession(
        date: _date,
        players: players,
        winner: winner,
        scores: scores,
        scoreGrid: grid,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        trackScores: _trackScores,
        winCondition: _winCondition,
        confrontationType: _confrontation,
        useTeams: useTeamsEffective,
        coopVictory: _isCoop ? _coopVictory : null,
        coopTeamCount: _isCoop ? _coopTeamCount : null,
        targetScore: _winCondition == BoardgameWinCondition.exactTarget
            ? _targetScore
            : null,
        status: _status,
        createdAt: widget.initial?.createdAt ?? DateTime.now(),
        shareId: widget.initial?.shareId ?? newPlayShareId(),
      );
    final item = widget.item;
    if (item != null &&
        Supabase.instance.client.auth.currentUser != null) {
      PlayShareService.instance.shareFinishedPlay(
        session: session,
        gameTitle: item.title,
        bggId: item.metadata?['bgg_id']?.toString(),
        imageUrl: item.imageUrl,
      );
    }
    Navigator.pop(context, session);
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
    final scheme = Theme.of(context).colorScheme;
    final canPickPlayers =
        _pickableProfiles.isNotEmpty &&
        Supabase.instance.client.auth.currentUser != null;
    final item = widget.item;
    final useTeamsEffective =
        _confrontation == BoardgameConfrontationType.teams ||
        (_isCoop && _coopTeamCount > 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Nouvelle partie' : 'Partie'),
        actions: [
          IconButton(
            onPressed: _submit,
            icon: const Icon(Icons.save_rounded),
            tooltip: 'Enregistrer',
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: BoardgamePlaySessionPage.maxContentWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (item != null) ...[
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child:
                            item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? BggNetworkImage(
                                url: item.imageUrl!,
                                boxedCover: true,
                              )
                            : ColoredBox(
                                color: scheme.primaryContainer,
                                child: Icon(
                                  Icons.casino,
                                  color: scheme.primary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(dateFmt.format(_date)),
              ),
              const SizedBox(height: 12),
              if (_status == BoardgamePlayStatus.inProgress)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timelapse,
                        size: 18,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Partie en cours',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(Icons.flag, size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Partie terminée',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Compter les points'),
                subtitle: const Text('Scores'),
                value: _trackScores,
                onChanged: (v) => setState(() => _trackScores = v),
              ),
              if (_trackScores) ...[
                const SizedBox(height: 8),
                Text(
                  'Type de jeu',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SegmentedButton<BoardgameConfrontationType>(
                  segments: BoardgameConfrontationType.values
                      .map(
                        (c) => ButtonSegment(
                          value: c,
                          label: Text(
                            c.shortLabel,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      )
                      .toList(),
                  selected: {_confrontation},
                  onSelectionChanged: (s) {
                    setState(() {
                      _confrontation = s.first;
                      _useTeams =
                          _confrontation == BoardgameConfrontationType.teams ||
                          (_confrontation ==
                                  BoardgameConfrontationType.cooperative &&
                              _coopTeamCount > 1);
                    });
                  },
                ),
                if (!_isCoop) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Condition de victoire',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  SegmentedButton<BoardgameWinCondition>(
                    segments: BoardgameWinCondition.selectable
                        .map(
                          (c) => ButtonSegment(
                            value: c,
                            label: Text(
                              c.shortLabel,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        )
                        .toList(),
                    selected: {_winCondition},
                    onSelectionChanged: (s) =>
                        setState(() => _winCondition = s.first),
                  ),
                ],
                if (_winCondition == BoardgameWinCondition.exactTarget &&
                    !_isCoop) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _targetScoreController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Score exact à atteindre',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (_isCoop) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Équipes coop',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _coopTeamCount > 1
                            ? () => setState(() => _coopTeamCount--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$_coopTeamCount'),
                      IconButton(
                        onPressed: _coopTeamCount < 12
                            ? () => setState(() => _coopTeamCount++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  if (_coopTeamCount <= 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Résultat face au jeu',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('Victoire'),
                          icon: Icon(Icons.check_circle_outline),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text('Défaite'),
                          icon: Icon(Icons.cancel_outlined),
                        ),
                      ],
                      selected: _coopVictory == null ? {} : {_coopVictory!},
                      emptySelectionAllowed: true,
                      onSelectionChanged: (s) =>
                          setState(() => _coopVictory = s.firstOrNull),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                BoardgameScoreGridEditor(
                  key: _gridKey,
                  initialGrid: _initialGrid,
                  suggestedPlayerNames: pastPlayerNamesFromSessions(
                    parseBoardgamePlays(widget.item?.metadata),
                  ),
                  useTeams: useTeamsEffective,
                  winCondition: _winCondition,
                  targetScore: _targetScore,
                  // Type de jeu pilote déjà Solo / Équipes / Coop — pas de toggle doublon.
                  onTeamsChanged: null,
                  onPickPlayer: canPickPlayers ? _pickPlayerFromContacts : null,
                  showScoreTable: true,
                  onQuickSave: _submit,
                  friendChoices: _friendChoices,
                  onFriendLinked: (name, friend) =>
                      PlayerAliasService.instance.linkFriend(
                        name,
                        profileId: friend.profileId,
                        username: friend.username,
                      ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _playersOnlyController,
                  decoration: const InputDecoration(
                    labelText: 'Joueurs',
                    hintText: 'Alice, Bob, Charlie',
                  ),
                ),
              ],
              if (!_isCoop) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _winnerController,
                  decoration: InputDecoration(
                    labelText: 'Gagnant (forcer manuellement)',
                    hintText: 'Couronne auto si vide',
                    prefixIcon: Icon(
                      Icons.emoji_events_outlined,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optionnel)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              if (_status == BoardgamePlayStatus.inProgress)
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _status = BoardgamePlayStatus.finished);
                    _submit();
                  },
                  icon: const Icon(Icons.flag_rounded),
                  label: const Text('Finir la partie'),
                )
              else
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Enregistrer la partie'),
                ),
              if (_status == BoardgamePlayStatus.inProgress) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Enregistrer (rester en cours)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
