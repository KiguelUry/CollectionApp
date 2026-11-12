import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/boardgame_play_session.dart';
import '../models/boardgame_score_grid.dart';
import '../models/collection_item.dart';
import '../models/friend_choice.dart';
import '../services/collection_local_cache.dart';
import '../services/friend_service.dart';
import '../services/inventory_service.dart';
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
    BoardgameScoreTemplate? template;
    DateTime? stamp;
    for (final s in sessions) {
      final t = s.scoreTemplate;
      if (t == null) continue;
      final at = s.createdAt ?? s.date;
      if (stamp == null || at.isAfter(stamp)) {
        stamp = at;
        template = t;
      }
    }
    if (template != null) meta['score_template'] = template.toJson();
    for (final session in sessions.reversed) {
      final library = session.presetLibrary;
      if (library == null) continue;
      meta['score_presets'] = [for (final preset in library) preset.toJson()];
      break;
    }
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
              if (session.winReason?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text('Motif : ${session.winReason}'),
              ],
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
  late bool _useTeams;
  late BoardgameWinCondition _winCondition;
  late BoardgameScoreTemplate _template;
  List<NamedScorePreset> _presets = const [];
  String? _activePresetName;
  String _presetBaseline = '';
  late BoardgameConfrontationType _confrontation;
  late BoardgamePlayStatus _status;
  late BoardgameScoreGrid _initialGrid;
  bool? _coopVictory;
  int _coopTeamCount = 1;
  final _winnerController = TextEditingController();
  final _winReasonController = TextEditingController();
  final _notesController = TextEditingController();
  final _playersOnlyController = TextEditingController();
  final _targetScoreController = TextEditingController();
  List<Map<String, dynamic>> _pickableProfiles = [];
  List<FriendChoice> _friendChoices = const [];
  bool _winnerManuallyForced = false;
  bool _motifManual = false;
  bool _applyingField = false;
  bool _draftReady = false;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    final t = widget.template;
    final seed = s ?? t;
    _date = s?.date ?? DateTime.now();
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
        _confrontation == BoardgameConfrontationType.oneVsAll ||
        (_confrontation == BoardgameConfrontationType.cooperative &&
            (seed?.coopTeamCount ?? 1) > 1);
    _winCondition = seed?.winCondition == BoardgameWinCondition.cooperative
        ? BoardgameWinCondition.highest
        : (seed?.winCondition ?? BoardgameWinCondition.highest);
    final unscored = seed != null &&
        seed.trackScores == false &&
        seed.scoreGrid == null &&
        seed.winCondition != BoardgameWinCondition.noScore &&
        seed.winCondition != BoardgameWinCondition.exactTarget;
    if (unscored && s == null) {
      _winCondition = BoardgameWinCondition.noScore;
    }
    if (s != null &&
        s.trackScores == false &&
        s.scoreGrid == null &&
        s.winCondition != BoardgameWinCondition.exactTarget &&
        s.winCondition != BoardgameWinCondition.customTemplate &&
        s.winCondition != BoardgameWinCondition.minimumThreshold) {
      _winCondition = BoardgameWinCondition.noScore;
    }
    _template = s?.scoreTemplate ??
        BoardgameScoreTemplate.fromMetadata(widget.item?.metadata) ??
        BoardgameScoreTemplate.empty;
    _presets = NamedScorePreset.listFrom(widget.item?.metadata);
    _activePresetName = _presetNameMatching(_template, _confrontation);
    _presetBaseline = _presetFingerprint();
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
    if (s == null && _template.lineNames.isNotEmpty) {
      final width = _initialGrid.players.length;
      _initialGrid = BoardgameScoreGrid(
        players: _initialGrid.players,
        teams: _initialGrid.teams,
        playerColors: _initialGrid.playerColors,
        teamColorMap: _initialGrid.teamColorMap,
        teamScoreMode: _initialGrid.teamScoreMode,
        rounds: [
          for (final line in _template.lines)
            if (line.name.trim().isNotEmpty)
              BoardgameScoreRound(
                label: line.name.trim(),
                malus: line.malus,
                scores: List<int?>.filled(width, null),
              ),
        ],
      );
    }
    if (s != null) {
      _winnerManuallyForced =
          BoardgamePlaySession.inferWinnerManuallyForced(s);
      if (_winnerManuallyForced) {
        _winnerController.text = s.winner ?? '';
      }
    }
    _notesController.text = s?.notes ?? '';
    _winReasonController.text = s?.winReason ?? '';
    _playersOnlyController.text = (s ?? t)?.players.join(', ') ?? '';
    _coopVictory = s?.coopVictory;
    _coopTeamCount = seed?.coopTeamCount ?? 1;
    if (seed?.targetScore != null) {
      _targetScoreController.text = '${seed!.targetScore}';
    }
    _loadProfiles();
    _restoreDraft();
  }

  String get _draftKey =>
      'play_draft_${widget.item?.id ?? 'loose'}_${widget.initial?.shareId ?? 'new'}';

  Future<void> _restoreDraft() async {
    if (widget.initial != null) {
      if (mounted) setState(() => _draftReady = true);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map && mounted) {
          _applyDraft(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _draftReady = true);
  }

  void _applyDraft(Map<String, dynamic> raw) {
    final date = DateTime.tryParse(raw['date']?.toString() ?? '');
    if (date != null) _date = date;
    _confrontation = BoardgameConfrontationType.fromJson(
      raw['confrontation']?.toString(),
    );
    _winCondition = BoardgameWinCondition.fromJson(raw['win']?.toString());
    _status = BoardgamePlayStatus.fromJson(raw['status']?.toString());
    _template = BoardgameScoreTemplate.fromJson(raw['template']) ??
        BoardgameScoreTemplate.empty;
    final gridRaw = raw['grid'];
    if (gridRaw is Map) {
      _initialGrid = BoardgameScoreGrid.fromJson(
        Map<String, dynamic>.from(gridRaw),
      );
    }
    _winnerManuallyForced = raw['winnerForced'] == true;
    _winnerController.text = raw['winner']?.toString() ?? '';
    _motifManual = raw['motifManual'] == true;
    _winReasonController.text = raw['reason']?.toString() ?? '';
    _notesController.text = raw['notes']?.toString() ?? '';
    _targetScoreController.text = raw['target']?.toString() ?? '';
    _playersOnlyController.text = raw['playersOnly']?.toString() ?? '';
    _coopVictory = raw['coopVictory'] is bool ? raw['coopVictory'] as bool : null;
    final teams = raw['coopTeams'];
    if (teams is num) _coopTeamCount = teams.round().clamp(1, 12);
    _useTeams = _confrontation == BoardgameConfrontationType.teams ||
        _confrontation == BoardgameConfrontationType.oneVsAll ||
        (_confrontation == BoardgameConfrontationType.cooperative &&
            _coopTeamCount > 1);
    _activePresetName = raw['activePreset']?.toString();
    // Le brouillon ne remplace jamais la bibliothèque de modèles du jeu.
    _presets = NamedScorePreset.listFrom(widget.item?.metadata);
    if (_activePresetName != null &&
        !_presets.any((preset) => preset.name == _activePresetName)) {
      _activePresetName = null;
    }
    _presetBaseline = _presetFingerprint();
  }

  void _scheduleDraft() {
    if (!_draftReady) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 350), _writeDraft);
  }

  Future<void> _writeDraft() async {
    try {
      final grid = _gridKey.currentState?.buildGrid() ?? _initialGrid;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _draftKey,
        jsonEncode({
          'date': _date.toIso8601String(),
          'confrontation': _confrontation.dbValue,
          'win': _winCondition.dbValue,
          'status': _status.dbValue,
          'template': _template.toJson(),
          'grid': grid.toJson(),
          'winner': _winnerController.text,
          'winnerForced': _winnerManuallyForced,
          'reason': _winReasonController.text,
          'motifManual': _motifManual,
          'notes': _notesController.text,
          'target': _targetScoreController.text,
          'playersOnly': _playersOnlyController.text,
          'coopVictory': _coopVictory,
          'coopTeams': _coopTeamCount,
          'activePreset': _activePresetName,
        }),
      );
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    _draftTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
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
            FriendChoice.fromFriendRow(f),
        ];
      });
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _writeDraft();
    _winnerController.dispose();
    _winReasonController.dispose();
    _notesController.dispose();
    _playersOnlyController.dispose();
    _targetScoreController.dispose();
    super.dispose();
  }

  int? get _targetScore => int.tryParse(_targetScoreController.text.trim());

  bool get _isCoop => _confrontation == BoardgameConfrontationType.cooperative;

  bool get _trackScores => _winCondition != BoardgameWinCondition.noScore;

  bool get _oneVsAll =>
      _confrontation == BoardgameConfrontationType.oneVsAll;

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

  String _presetFingerprint() {
    final lines = _template.lines
        .map((line) => '${line.name}:${line.malus}')
        .join(',');
    final rules = _template.rules
        .map(
          (rule) =>
              '${rule.target.name}:${rule.op.name}:${rule.value}:${rule.lineName}:${rule.cellOp?.name}:${rule.cellValue}:${rule.link?.name}',
        )
        .join(';');
    return '${_confrontation.dbValue}|${_template.matchAll}|$lines|$rules';
  }

  String? _presetNameMatching(
    BoardgameScoreTemplate template,
    BoardgameConfrontationType confrontation,
  ) {
    final probe = _fingerprintOf(confrontation, template);
    for (final preset in _presets) {
      if (_fingerprintOf(preset.confrontation, preset.template) == probe) {
        return preset.name;
      }
    }
    return null;
  }

  String _fingerprintOf(
    BoardgameConfrontationType confrontation,
    BoardgameScoreTemplate template,
  ) {
    final lines = template.lines
        .map((line) => '${line.name}:${line.malus}')
        .join(',');
    final rules = template.rules
        .map(
          (rule) =>
              '${rule.target.name}:${rule.op.name}:${rule.value}:${rule.lineName}:${rule.cellOp?.name}:${rule.cellValue}:${rule.link?.name}',
        )
        .join(';');
    return '${confrontation.dbValue}|${template.matchAll}|$lines|$rules';
  }

  Future<bool> _maybeSavePreset() async {
    if (_winCondition != BoardgameWinCondition.customTemplate || _isCoop) {
      return true;
    }
    final hasContent =
        _template.lines.isNotEmpty || _template.rules.isNotEmpty;
    if (!hasContent || _presetFingerprint() == _presetBaseline) return true;
    final nameCtrl = TextEditingController(text: _activePresetName ?? '');
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enregistrer ce modèle ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Veux-tu enregistrer ce modèle personnalisé ? Si oui, sous quel nom ?',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom du modèle',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Non, juste la partie'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx, name);
            },
            child: const Text('Enregistrer le modèle'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (!mounted || choice == null) return false;
    if (choice.isEmpty) return true;
    final preset = NamedScorePreset(
      name: choice,
      confrontation: _confrontation,
      template: _template,
    );
    final next = [
      for (final existing in _presets)
        if (existing.name.toLowerCase() != choice.toLowerCase()) existing,
      preset,
    ];
    setState(() {
      _presets = next;
      _activePresetName = choice;
      _presetBaseline = _presetFingerprint();
    });
    return true;
  }

  void _applyPreset(NamedScorePreset? preset) {
    if (preset == null) {
      setState(() {
        _activePresetName = null;
        _template = const BoardgameScoreTemplate();
        _presetBaseline = _presetFingerprint();
      });
      _gridKey.currentState?.setLineSpecs(const []);
      return;
    }
    setState(() {
      _activePresetName = preset.name;
      _confrontation = preset.confrontation;
      _useTeams = preset.confrontation == BoardgameConfrontationType.teams ||
          preset.confrontation == BoardgameConfrontationType.oneVsAll;
      _winCondition = BoardgameWinCondition.customTemplate;
      _template = preset.template;
      _presetBaseline = _fingerprintOf(preset.confrontation, preset.template);
    });
    _gridKey.currentState?.setLineSpecs(preset.template.lines);
  }

  BoardgameScoreTemplate get _liveTemplate {
    final lines = _gridKey.currentState?.lineSpecs() ?? _template.lines;
    return BoardgameScoreTemplate(
      lines: lines,
      rules: _template.rules,
      matchAll: _template.matchAll,
    );
  }

  Future<void> _persistPresetLibrary() async {
    final item = widget.item;
    if (item == null) return;
    final meta = Map<String, dynamic>.from(item.metadata ?? {});
    meta['score_presets'] = [for (final preset in _presets) preset.toJson()];
    final live = item.metadata;
    if (live != null) {
      live
        ..clear()
        ..addAll(meta);
    }
    InventoryService.patchRow(item.id, (row) => row['metadata'] = meta);
    await CollectionLocalCache.patchItemMetadata(item.id, meta);
    try {
      await Supabase.instance.client
          .from('collection_items')
          .update({'metadata': meta}).eq('id', item.id);
    } catch (_) {}
  }

  Future<String?> _askPresetName({String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nom du modèle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nom'),
          onTapOutside: (_) =>
              FocusManager.instance.primaryFocus?.unfocus(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(ctx, value);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    final name = chosen?.trim() ?? '';
    if (!mounted || name.isEmpty) return null;
    return name;
  }

  Future<void> _savePresetNow() async {
    var name = _activePresetName?.trim() ?? '';
    if (name.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enregistrer le template'),
          content: Text(
            '« $name » est le modèle sélectionné. Tu peux le mettre à jour, ou en enregistrer un nouveau.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'new'),
              child: const Text('Nouveau nom'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'update'),
              child: const Text('Mettre à jour'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'new') {
        final named = await _askPresetName();
        if (named == null) return;
        name = named;
      }
    } else {
      final named = await _askPresetName();
      if (named == null) return;
      name = named;
    }
    final preset = NamedScorePreset(
      name: name,
      confrontation: _confrontation,
      template: _liveTemplate,
    );
    setState(() {
      _presets = [
        for (final existing in _presets)
          if (existing.name.toLowerCase() != name.toLowerCase()) existing,
        preset,
      ];
      _activePresetName = name;
      _template = preset.template;
      _presetBaseline = _presetFingerprint();
    });
    await _persistPresetLibrary();
    _scheduleDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Modèle « $name » enregistré')),
    );
  }

  Future<void> _deleteActivePreset() async {
    final name = _activePresetName;
    if (name == null) return;
    setState(() {
      _presets = [
        for (final preset in _presets)
          if (preset.name.toLowerCase() != name.toLowerCase()) preset,
      ];
      _activePresetName = null;
      _presetBaseline = _presetFingerprint();
    });
    await _persistPresetLibrary();
    _scheduleDraft();
  }

  Widget _presetPicker() {
    const fresh = '__new__';
    final selected = _presets.any((preset) => preset.name == _activePresetName)
        ? _activePresetName!
        : fresh;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('preset-$selected-${_presets.length}'),
            initialValue: selected,
            isExpanded: true,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: _thinField,
            items: [
              for (final preset in _presets)
                DropdownMenuItem(
                  value: preset.name,
                  child: Text(preset.name, overflow: TextOverflow.ellipsis),
                ),
              const DropdownMenuItem(
                value: fresh,
                child: Text('+ Nouveau'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              if (value == fresh) {
                _applyPreset(null);
                return;
              }
              for (final preset in _presets) {
                if (preset.name == value) {
                  _applyPreset(preset);
                  return;
                }
              }
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: _savePresetNow,
                  child: const Text('Enregistrer le template'),
                ),
                TextButton(
                  onPressed:
                      _activePresetName == null ? null : _deleteActivePreset,
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _contenderNames() {
    if (!_trackScores) {
      return _playersOnlyController.text
          .split(',')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList();
    }
    final grid = _gridKey.currentState?.buildGrid() ?? _initialGrid;
    if (grid.hasTeams) {
      final teams = <String>[];
      for (final team in grid.teams) {
        final name = team?.trim() ?? '';
        if (name.isNotEmpty && !teams.contains(name)) teams.add(name);
      }
      if (teams.isNotEmpty) return teams;
    }
    return grid.activePlayers;
  }

  Widget _winnerPicker(ColorScheme scheme) {
    final names = _contenderNames();
    final current = _winnerController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _winCondition == BoardgameWinCondition.noScore
              ? 'Gagnant'
              : 'Gagnant',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final name in names)
              ChoiceChip(
                label: Text(name),
                selected: current == name,
                onSelected: (_) {
                  setState(() {
                    _winnerManuallyForced = true;
                    _winnerController.text = name;
                  });
                  _scheduleDraft();
                },
              ),
            ChoiceChip(
              label: const Text('Aucun / Égalité'),
              selected: _winnerManuallyForced && current.isEmpty,
              onSelected: (_) {
                setState(() {
                  _winnerManuallyForced = true;
                  _winnerController.clear();
                });
                _scheduleDraft();
              },
            ),
            if (_winnerManuallyForced &&
                _winCondition != BoardgameWinCondition.noScore)
              ActionChip(
                label: const Text('Auto'),
                onPressed: () {
                  setState(() => _winnerManuallyForced = false);
                  _onGridChanged();
                },
              ),
          ],
        ),
        if (_winCondition != BoardgameWinCondition.noScore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _winnerManuallyForced
                  ? 'Forçage manuel actif'
                  : 'Auto depuis les scores',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Future<void> _submit() async {
    List<String> players;
    BoardgameScoreGrid? grid;
    Map<String, int>? scores;
    final useTeamsEffective =
        _confrontation == BoardgameConfrontationType.teams ||
        _confrontation == BoardgameConfrontationType.oneVsAll ||
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
      if ((_winCondition == BoardgameWinCondition.exactTarget ||
              _winCondition == BoardgameWinCondition.minimumThreshold) &&
          _targetScore == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indique le score à atteindre.')),
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

    final liveLines = _gridKey.currentState?.lineSpecs();
    if (liveLines != null &&
        _winCondition == BoardgameWinCondition.customTemplate) {
      _template = BoardgameScoreTemplate(
        lines: liveLines,
        rules: _template.rules,
        matchAll: _template.matchAll,
      );
    }
    if (!await _maybeSavePreset()) return;
    if (!mounted) return;

    final noScore = _winCondition == BoardgameWinCondition.noScore;
    final savedTemplate = _winCondition == BoardgameWinCondition.customTemplate
        ? BoardgameScoreTemplate(
            lines: _gridKey.currentState?.lineSpecs() ?? _template.lines,
            rules: _template.rules,
            matchAll: _template.matchAll,
          )
        : _template;
    final autoNames = noScore
        ? const <String>[]
        : grid?.winnerNames(
              _winCondition,
              targetScore: _targetScore,
              template: savedTemplate,
            ) ??
            const <String>[];
    final manualWinner = _winnerController.text.trim();
    final autoWinnerStr = _isCoop
        ? null
        : (autoNames.isEmpty ? null : autoNames.join(' & '));
    final winner = noScore
        ? (manualWinner.isEmpty ? null : manualWinner)
        : (_winnerManuallyForced
            ? (manualWinner.isEmpty ? null : manualWinner)
            : autoWinnerStr);
    final winReason = _winReasonController.text.trim();

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
        targetScore: _winCondition == BoardgameWinCondition.exactTarget ||
                _winCondition == BoardgameWinCondition.minimumThreshold
            ? _targetScore
            : null,
        scoreTemplate: _winCondition == BoardgameWinCondition.customTemplate
            ? savedTemplate
            : null,
        status: _status,
        createdAt: widget.initial?.createdAt ?? DateTime.now(),
        shareId: widget.initial?.shareId ?? newPlayShareId(),
        winnerManuallyForced: _winnerManuallyForced,
        winReason: winReason.isEmpty ? null : winReason,
        presetLibrary: _presets,
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
    await _clearDraft();
    if (!mounted) return;
    Navigator.pop(context, session);
  }

  void _onGridChanged() {
    final state = _gridKey.currentState;
    final grid = state?.buildGrid();
    if (state == null || grid == null) return;
    _initialGrid = grid;
    _scheduleDraft();
    if (_isCoop || _winCondition == BoardgameWinCondition.noScore) return;
    BoardgameScoreTemplate? template;
    if (_winCondition == BoardgameWinCondition.customTemplate) {
      final specs = state.lineSpecs();
      template = BoardgameScoreTemplate(
        lines: specs.isEmpty ? _template.lines : specs,
        rules: _template.rules,
        matchAll: _template.matchAll,
      );
    }
    final names = grid.winnerNames(
      _winCondition,
      targetScore: _targetScore,
      template: template,
    );
    final summary = grid.autoWinReason(
      _winCondition,
      targetScore: _targetScore,
      template: template,
    );
    _applyingField = true;
    if (!_winnerManuallyForced) {
      _winnerController.text = names.join(' & ');
    }
    if (!_motifManual) {
      _winReasonController.text = summary ?? '';
    }
    _applyingField = false;
    if (template == null) return;
    final synced = template;
    final previous = _template.lines
        .map((line) => '${line.name}:${line.malus}')
        .join('|');
    final next = synced.lines
        .map((line) => '${line.name}:${line.malus}')
        .join('|');
    if (previous != next) setState(() => _template = synced);
  }

  Widget _playMenus(BuildContext context) {
    final showThreshold = _trackScores &&
        !_isCoop &&
        (_winCondition == BoardgameWinCondition.exactTarget ||
            _winCondition == BoardgameWinCondition.minimumThreshold);
    final typeMenu = DropdownButtonFormField<BoardgameConfrontationType>(
      key: ValueKey(_confrontation),
      initialValue: _confrontation,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Type de jeu',
      ),
      items: [
        for (final c in BoardgameConfrontationType.values)
          DropdownMenuItem(value: c, child: Text(c.label)),
      ],
      onChanged: (c) {
        if (c == null) return;
        setState(() {
          _confrontation = c;
          _useTeams = c == BoardgameConfrontationType.teams ||
              c == BoardgameConfrontationType.oneVsAll ||
              (c == BoardgameConfrontationType.cooperative &&
                  _coopTeamCount > 1);
        });
      },
    );
    final winMenu = DropdownButtonFormField<BoardgameWinCondition>(
      key: ValueKey(_winCondition),
      initialValue: _winCondition,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Condition de victoire',
      ),
      items: [
        for (final c in BoardgameWinCondition.selectableFor(_winCondition))
          DropdownMenuItem(value: c, child: Text(c.label)),
      ],
      onChanged: (c) {
        if (c == null) return;
        setState(() => _winCondition = c);
        _onGridChanged();
      },
    );
    final threshold = showThreshold ? _thresholdBubble() : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 560;
        if (!sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              typeMenu,
              if (!_isCoop) ...[
                const SizedBox(height: 8),
                winMenu,
              ],
              if (threshold != null) ...[
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: threshold),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 260, child: typeMenu),
            if (!_isCoop) SizedBox(width: 300, child: winMenu),
            ?threshold,
          ],
        );
      },
    );
  }

  Widget _thresholdBubble() {
    final label = _winCondition == BoardgameWinCondition.minimumThreshold
        ? 'Seuil minimum'
        : 'Score exact';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label : '),
          SizedBox(
            width: 56,
            child: TextField(
              controller: _targetScoreController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (_) {
                setState(() {});
                _onGridChanged();
              },
            ),
          ),
        ],
      ),
    );
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
        _confrontation == BoardgameConfrontationType.oneVsAll ||
        (_isCoop && _coopTeamCount > 1);

    if (!_draftReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          item != null && item.title.trim().isNotEmpty
              ? item.title
              : (widget.initial == null ? 'Nouvelle partie' : 'Partie'),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _submit,
            icon: const Icon(Icons.save_rounded),
            tooltip: 'Enregistrer',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900 && _trackScores;
          final header = <Widget>[
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
              const SizedBox(height: 8),
              _playMenus(context),
          ];
          final setup = <Widget>[
                if (_winCondition == BoardgameWinCondition.customTemplate &&
                    !_isCoop) ...[
                  _presetPicker(),
                  _TemplateFields(
                    template: _template,
                    onChanged: (next) {
                      _gridKey.currentState?.setLineSpecs(next.lines);
                      final lines =
                          _gridKey.currentState?.lineSpecs() ?? next.lines;
                      final grid = _gridKey.currentState?.buildGrid();
                      setState(() {
                        _template = BoardgameScoreTemplate(
                          lines: lines,
                          rules: next.rules,
                          matchAll: next.matchAll,
                        );
                        if (grid != null) _initialGrid = grid;
                      });
                    },
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
          ];
          final footer = <Widget>[
              if (!_isCoop) ...[
                const SizedBox(height: 16),
                _winnerPicker(scheme),
                const SizedBox(height: 8),
                TextField(
                  controller: _winReasonController,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) {
                    if (_applyingField) return;
                    _motifManual = _winReasonController.text.trim().isNotEmpty;
                    _scheduleDraft();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Motif (optionnel)',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onChanged: (_) => _scheduleDraft(),
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
          ];
          Widget editor(bool side) {
            return BoardgameScoreGridEditor(
              key: _gridKey,
              wideLayout: side,
              leading: side
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...header,
                        if (_trackScores) ...setup,
                      ],
                    )
                  : null,
              trailing: side
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: footer,
                    )
                  : null,
              initialGrid: _initialGrid,
              onScoresChanged: _onGridChanged,
              suggestedPlayerNames: pastPlayerNamesFromSessions(
                parseBoardgamePlays(widget.item?.metadata),
              ),
              useTeams: useTeamsEffective,
              oneVsAll: _oneVsAll,
              template: _template,
              winCondition: _winCondition,
              targetScore: _targetScore,
              onTeamsChanged: null,
              onPickPlayer: canPickPlayers ? _pickPlayerFromContacts : null,
              showScoreTable: _winCondition != BoardgameWinCondition.noScore,
              onQuickSave: _submit,
              friendChoices: _friendChoices,
              onFriendLinked: (name, friend) =>
                  PlayerAliasService.instance.linkFriend(
                    name,
                    profileId: friend.profileId,
                    username: friend.username,
                  ),
            );
          }
          if (wide) return editor(true);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: BoardgamePlaySessionPage.maxContentWidth,
              ),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  ...header,
                  if (_trackScores) ...[
                    ...setup,
                    const SizedBox(height: 8),
                    editor(false),
                  ] else ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _playersOnlyController,
                      decoration: const InputDecoration(
                        labelText: 'Joueurs',
                      ),
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                    ),
                  ],
                  ...footer,
                ],
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

class _TemplateFields extends StatefulWidget {
  final BoardgameScoreTemplate template;
  final ValueChanged<BoardgameScoreTemplate> onChanged;

  const _TemplateFields({required this.template, required this.onChanged});

  @override
  State<_TemplateFields> createState() => _TemplateFieldsState();
}

class _TemplateFieldsState extends State<_TemplateFields> {
  late List<ScoreLineSpec> _lines;
  late List<ScoreRule> _rules;
  late List<TextEditingController> _values;
  late List<TextEditingController> _cellValues;
  late bool _matchAll;
  bool _rulesOpen = true;

  @override
  void initState() {
    super.initState();
    _lines = [...widget.template.lines];
    _rules = [...widget.template.rules];
    _matchAll = widget.template.matchAll;
    _values = [
      for (final rule in _rules)
        TextEditingController(text: rule.value?.toString() ?? ''),
    ];
    _cellValues = [
      for (final rule in _rules)
        TextEditingController(
          text: (rule.cellValue ?? 1).toString(),
        ),
    ];
  }

  @override
  void didUpdateWidget(covariant _TemplateFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.template.lines;
    final same = incoming.length == _lines.length &&
        [
          for (var i = 0; i < incoming.length; i++)
            incoming[i].name == _lines[i].name &&
                incoming[i].malus == _lines[i].malus,
        ].every((sameLine) => sameLine);
    if (!same) _lines = [...incoming];
  }

  @override
  void dispose() {
    for (final controller in _values) {
      controller.dispose();
    }
    for (final controller in _cellValues) {
      controller.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      BoardgameScoreTemplate(
        lines: [
          for (final line in _lines)
            if (line.name.trim().isNotEmpty)
              ScoreLineSpec(line.name.trim(), sign: line.sign),
        ],
        rules: [
          for (var i = 0; i < _rules.length; i++)
            ScoreRule(
              target: _rules[i].target,
              op: _rules[i].countsCategories
                  ? _comparisonOp(_rules[i].op)
                  : _rules[i].op,
              value: _rules[i].needsValue
                  ? int.tryParse(_values[i].text.trim())
                  : null,
              lineName: _rules[i].target == ScoreRuleTarget.namedLine
                  ? _rules[i].lineName
                  : null,
              link: i == 0 ? null : _rules[i].link,
              cellOp: _rules[i].countsCategories
                  ? _comparisonOp(_rules[i].effectiveCellOp)
                  : null,
              cellValue: _rules[i].countsCategories
                  ? int.tryParse(_cellValues[i].text.trim()) ?? 1
                  : null,
            ),
        ],
        matchAll: _matchAll,
      ),
    );
  }

  Future<void> _rename(int index) async {
    final controller = TextEditingController(text: _lines[index].name);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer la catégorie'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nom'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    final name = next?.trim() ?? '';
    if (name.isEmpty || !mounted) return;
    setState(() {
      _lines[index] = ScoreLineSpec(name, sign: _lines[index].sign);
    });
    _emit();
  }

  String _targetKey(ScoreRule rule) {
    if (rule.target == ScoreRuleTarget.namedLine) {
      return 'line:${rule.lineName ?? ''}';
    }
    return rule.target.name;
  }

  void _setTarget(int index, String key) {
    ScoreRule rule;
    if (key.startsWith('line:')) {
      rule = ScoreRule(
        target: ScoreRuleTarget.namedLine,
        op: _rules[index].op,
        value: _rules[index].value,
        lineName: key.substring(5),
        link: _rules[index].link,
      );
    } else {
      final target = ScoreRuleTarget.values.firstWhere(
        (item) => item.name == key,
        orElse: () => ScoreRuleTarget.total,
      );
      final counts = target == ScoreRuleTarget.filledLineCount;
      rule = ScoreRule(
        target: target,
        op: counts ? _comparisonOp(_rules[index].op) : _rules[index].op,
        value: _rules[index].value,
        cellOp: counts ? ScoreRuleOp.gte : null,
        cellValue: counts ? int.tryParse(_cellValues[index].text.trim()) ?? 1 : null,
        link: _rules[index].link,
      );
      if (counts && _cellValues[index].text.trim().isEmpty) {
        _cellValues[index].text = '1';
      }
    }
    setState(() => _rules[index] = rule);
    _emit();
  }

  Widget _ruleCard(int i, List<String> names, ColorScheme scheme) {
    final rule = _rules[i];
    final target = DropdownButtonFormField<String>(
      key: ValueKey('target-$i-${_targetKey(rule)}-$names'),
      initialValue: _targetKey(rule),
      isExpanded: true,
      style: TextStyle(fontSize: 13, color: scheme.onSurface),
      decoration: _thinField,
      items: [
        const DropdownMenuItem(value: 'total', child: Text('Le score total')),
        const DropdownMenuItem(
          value: 'anyLine',
          child: Text('Au moins une catégorie'),
        ),
        const DropdownMenuItem(
          value: 'filledLineCount',
          child: Text('Plusieurs catégories différentes'),
        ),
        const DropdownMenuItem(
          value: 'weakestLine',
          child: Text('La catégorie la plus faible'),
        ),
        const DropdownMenuItem(
          value: 'leadGap',
          child: Text('L\'écart avec le 2e'),
        ),
        const DropdownMenuItem(
          value: 'everyLine',
          child: Text('Chaque catégorie (toutes)'),
        ),
        for (final name in names)
          DropdownMenuItem(
            value: 'line:$name',
            child: Text('La catégorie : $name'),
          ),
        if (rule.target == ScoreRuleTarget.namedLine &&
            !names.contains(rule.lineName))
          DropdownMenuItem(
            value: _targetKey(rule),
            child: Text('La catégorie : ${rule.lineName ?? ''}'),
          ),
      ],
      onChanged: (key) {
        if (key == null) return;
        _setTarget(i, key);
      },
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Monter',
                  onPressed: i == 0 ? null : () => _moveRule(i, i - 1),
                  icon: const Icon(Icons.arrow_upward, size: 16),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Descendre',
                  onPressed: i == _rules.length - 1
                      ? null
                      : () => _moveRule(i, i + 1),
                  icon: const Icon(Icons.arrow_downward, size: 16),
                ),
                Expanded(child: target),
                IconButton(
                  tooltip: 'Retirer',
                  onPressed: () {
                    setState(() {
                      _rules.removeAt(i);
                      _values.removeAt(i).dispose();
                      _cellValues.removeAt(i).dispose();
                    });
                    _emit();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (rule.countsCategories) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 168,
                    child: _opMenu(
                      key: 'count-$i-${_comparisonOp(rule.op).name}',
                      value: _comparisonOp(rule.op),
                      phrases: _countOpPhrase,
                      onChanged: (op) {
                        setState(() {
                          _rules[i] = ScoreRule(
                            target: rule.target,
                            op: op,
                            value: rule.value,
                            cellOp: rule.effectiveCellOp,
                            cellValue:
                                int.tryParse(_cellValues[i].text.trim()) ?? 1,
                            link: rule.link,
                          );
                        });
                        _emit();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: _values[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: _thinField,
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      onChanged: (_) => _emit(),
                    ),
                  ),
                  const Text('catégories différentes'),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('ont chacune'),
                  SizedBox(
                    width: 150,
                    child: _opMenu(
                      key: 'cell-$i-${rule.effectiveCellOp.name}',
                      value: _comparisonOp(rule.effectiveCellOp),
                      phrases: _pointOpPhrase,
                      onChanged: (op) {
                        setState(() {
                          _rules[i] = ScoreRule(
                            target: rule.target,
                            op: _comparisonOp(rule.op),
                            value: rule.value,
                            cellOp: op,
                            cellValue:
                                int.tryParse(_cellValues[i].text.trim()) ?? 1,
                            link: rule.link,
                          );
                        });
                        _emit();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: _cellValues[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: _thinField,
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      onChanged: (_) => _emit(),
                    ),
                  ),
                  const Text('point(s)'),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _opMenu(
                        key: 'op-$i-${rule.op.name}',
                        value: rule.op,
                        ops: ScoreRuleOp.values,
                        phrases: (op) => _ruleOpPhrase(
                          op,
                          category: rule.target != ScoreRuleTarget.total &&
                              rule.target != ScoreRuleTarget.leadGap,
                        ),
                        onChanged: (op) {
                          setState(() {
                            _rules[i] = ScoreRule(
                              target: rule.target,
                              op: op,
                              value: rule.value,
                              lineName: rule.lineName,
                              link: rule.link,
                            );
                          });
                          _emit();
                        },
                      ),
                    ),
                    if (rule.needsValue) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: _values[i],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: _thinField,
                          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      onChanged: (_) => _emit(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _groupedRules(List<String> names, ColorScheme scheme) {
    final groups = <List<int>>[];
    for (var i = 0; i < _rules.length; i++) {
      final join = _rules[i].link ??
          (_matchAll ? ScoreRuleJoin.and : ScoreRuleJoin.or);
      if (i == 0 || join == ScoreRuleJoin.or) {
        groups.add([i]);
      } else {
        groups.last.add(i);
      }
    }
    final widgets = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      final indexes = groups[g];
      if (g > 0) widgets.add(_joinBar(indexes.first, scheme));
      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var k = 0; k < indexes.length; k++) ...[
                if (k > 0) _joinBar(indexes[k], scheme),
                _ruleCard(indexes[k], names, scheme),
              ],
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  ScoreRule _withLink(ScoreRule rule, ScoreRuleJoin? link) {
    return ScoreRule(
      target: rule.target,
      op: rule.op,
      value: rule.value,
      lineName: rule.lineName,
      cellOp: rule.cellOp,
      cellValue: rule.cellValue,
      link: link,
    );
  }

  void _setLink(int index, ScoreRuleJoin join) {
    setState(() {
      for (var i = 1; i < _rules.length; i++) {
        final current = _rules[i].link ??
            (_matchAll ? ScoreRuleJoin.and : ScoreRuleJoin.or);
        _rules[i] = _withLink(_rules[i], i == index ? join : current);
      }
      _matchAll = _rules.skip(1).every((rule) => rule.link != ScoreRuleJoin.or);
    });
    _emit();
  }

  void _moveRule(int from, int to) {
    if (to < 0 || to >= _rules.length) return;
    setState(() {
      final rule = _rules.removeAt(from);
      final value = _values.removeAt(from);
      final cell = _cellValues.removeAt(from);
      _rules.insert(to, rule);
      _values.insert(to, value);
      _cellValues.insert(to, cell);
      if (_rules.isNotEmpty) _rules[0] = _withLink(_rules[0], null);
    });
    _emit();
  }

  Widget _joinBar(int index, ColorScheme scheme) {
    final selected = _rules[index].link ??
        (_matchAll ? ScoreRuleJoin.and : ScoreRuleJoin.or);
    Widget word(ScoreRuleJoin join, String label) {
      final on = selected == join;
      return InkWell(
        onTap: () => _setLink(index, join),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: on ? FontWeight.w500 : FontWeight.w400,
              color: on ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: scheme.outlineVariant)),
          const SizedBox(width: 8),
          word(ScoreRuleJoin.or, 'ou'),
          Text(' / ', style: TextStyle(color: scheme.outline, fontSize: 12)),
          word(ScoreRuleJoin.and, 'et'),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: scheme.outlineVariant)),
        ],
      ),
    );
  }

  Widget _opMenu({
    required String key,
    required ScoreRuleOp value,
    required ValueChanged<ScoreRuleOp> onChanged,
    required String Function(ScoreRuleOp op) phrases,
    List<ScoreRuleOp> ops = _comparisonOps,
  }) {
    return DropdownButtonFormField<ScoreRuleOp>(
      key: ValueKey(key),
      initialValue: value,
      isExpanded: true,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: _thinField,
      items: [
        for (final op in ops)
          DropdownMenuItem(
            value: op,
            child: Text(phrases(op), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (op) {
        if (op == null) return;
        onChanged(op);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = <String>[];
    for (final line in _lines) {
      final name = line.name.trim();
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text('Catégories', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _lines.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor:
                          _lines[i].malus ? scheme.error : scheme.primary,
                    ),
                    onPressed: () {
                      setState(() {
                        _lines[i] = ScoreLineSpec(
                          _lines[i].name,
                          sign: _lines[i].malus
                              ? ScoreLineSign.bonus
                              : ScoreLineSign.malus,
                        );
                      });
                      _emit();
                    },
                    child: Text(
                      _lines[i].malus ? '−' : '+',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  InputChip(
                    label: Text(
                      _lines[i].name.trim().isEmpty
                          ? 'Sans nom'
                          : _lines[i].name,
                    ),
                    onPressed: () => _rename(i),
                    onDeleted: () {
                      setState(() => _lines.removeAt(i));
                      _emit();
                    },
                  ),
                ],
              ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _lines.add(ScoreLineSpec('Catégorie ${_lines.length + 1}'));
                });
                _emit();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter une catégorie'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Toucher + ou − sur une catégorie pour en faire un bonus ou un malus.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _rules.isEmpty
                    ? 'Condition(s) de victoire'
                    : 'Condition(s) de victoire (${_rules.length})',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton(
              tooltip: _rulesOpen ? 'Masquer' : 'Afficher',
              onPressed: () => setState(() => _rulesOpen = !_rulesOpen),
              icon: Icon(
                _rulesOpen ? Icons.expand_less : Icons.expand_more,
              ),
            ),
          ],
        ),
        if (_rulesOpen) ..._groupedRules(names, scheme),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _rules.add(
                  ScoreRule(
                    target: ScoreRuleTarget.total,
                    op: ScoreRuleOp.gte,
                    link: _rules.isEmpty ? null : ScoreRuleJoin.or,
                  ),
                );
                _values.add(TextEditingController());
                _cellValues.add(TextEditingController(text: '1'));
              });
              _emit();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter une condition de victoire'),
          ),
        ),
      ],
    );
  }
}

const _comparisonOps = <ScoreRuleOp>[
  ScoreRuleOp.gte,
  ScoreRuleOp.eq,
  ScoreRuleOp.lte,
  ScoreRuleOp.gt,
  ScoreRuleOp.lt,
];

ScoreRuleOp _comparisonOp(ScoreRuleOp op) =>
    _comparisonOps.contains(op) ? op : ScoreRuleOp.gte;

const _thinField = InputDecoration(
  isDense: true,
  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
);

String _ruleOpPhrase(ScoreRuleOp op, {required bool category}) {
  if (category) {
    return switch (op) {
      ScoreRuleOp.gte => 'atteint au moins (≥)',
      ScoreRuleOp.eq => 'atteint exactement (=)',
      ScoreRuleOp.lte => 'atteint au maximum (≤)',
      ScoreRuleOp.gt => 'atteint plus de (>)',
      ScoreRuleOp.lt => 'atteint moins de (<)',
      ScoreRuleOp.highest => 'le plus élevé',
      ScoreRuleOp.lowest => 'le plus bas',
    };
  }
  return switch (op) {
    ScoreRuleOp.gte => "est d'au moins (≥)",
    ScoreRuleOp.eq => 'est exactement (=)',
    ScoreRuleOp.lte => "est d'au maximum (≤)",
    ScoreRuleOp.gt => 'est plus de (>)',
    ScoreRuleOp.lt => 'est moins de (<)',
    ScoreRuleOp.highest => 'le plus élevé',
    ScoreRuleOp.lowest => 'le plus bas',
  };
}

String _countOpPhrase(ScoreRuleOp op) => switch (op) {
      ScoreRuleOp.gte => 'Au moins (≥)',
      ScoreRuleOp.eq => 'Exactement (=)',
      ScoreRuleOp.lte => 'Au maximum (≤)',
      ScoreRuleOp.gt => 'Plus de (>)',
      ScoreRuleOp.lt => 'Moins de (<)',
      _ => 'Au moins (≥)',
    };

String _pointOpPhrase(ScoreRuleOp op) => switch (op) {
      ScoreRuleOp.gte => 'au moins (≥)',
      ScoreRuleOp.eq => 'exactement (=)',
      ScoreRuleOp.lte => 'au maximum (≤)',
      ScoreRuleOp.gt => 'plus de (>)',
      ScoreRuleOp.lt => 'moins de (<)',
      _ => 'au moins (≥)',
    };

String opLabel(ScoreRuleOp op) => switch (op) {
      ScoreRuleOp.gte => '>=',
      ScoreRuleOp.eq => '=',
      ScoreRuleOp.lte => '<=',
      ScoreRuleOp.gt => '>',
      ScoreRuleOp.lt => '<',
      ScoreRuleOp.highest => 'Plus haut score',
      ScoreRuleOp.lowest => 'Plus petit score',
    };
