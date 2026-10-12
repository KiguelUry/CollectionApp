import 'package:flutter/material.dart';

import '../models/boardgame_play_session.dart';
import '../models/collection_item.dart';
import '../utils/boardgame_play_stats.dart';
import 'boardgame_play_history_panel.dart';
import 'detail_bento_tile.dart';
import 'group_rules_panel.dart';

enum _PlayHubTab { none, history, stats, ranking }

/// Hub « Parties & scores » : une tuile qui ouvre 3 sous-choix.
class BoardgamePlayHubBento extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;
  final TextEditingController? personalRulesController;

  const BoardgamePlayHubBento({
    super.key,
    required this.item,
    required this.readOnly,
    required this.onMetadataChanged,
    this.personalRulesController,
  });

  @override
  State<BoardgamePlayHubBento> createState() => _BoardgamePlayHubBentoState();
}

class _BoardgamePlayHubBentoState extends State<BoardgamePlayHubBento> {
  bool _hubOpen = false;
  _PlayHubTab _tab = _PlayHubTab.none;

  List<BoardgamePlaySession> get _sessions =>
      parseBoardgamePlays(widget.item.metadata);

  void _openHub() {
    setState(() {
      _hubOpen = !_hubOpen;
      if (!_hubOpen) _tab = _PlayHubTab.none;
    });
  }

  void _select(_PlayHubTab tab) {
    setState(() => _tab = _tab == tab ? _PlayHubTab.none : tab);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Colors.orange.shade800;
    final sessions = _sessions;
    final stats = BoardgameRankingStats.fromSessions(sessions);
    final topWin = stats.winPodium.isNotEmpty ? stats.winPodium.first : null;
    final subtitle = sessions.isEmpty
        ? 'Historique · stats · classement'
        : topWin != null
            ? '${sessions.length} partie${sessions.length > 1 ? 's' : ''} · ${topWin.name}'
            : '${sessions.length} partie${sessions.length > 1 ? 's' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailBentoTile(
          icon: Icons.casino_outlined,
          title: 'Parties & scores',
          subtitle: subtitle,
          accent: accent,
          expanded: _hubOpen,
          onTap: _openHub,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailBentoSubTile(
                icon: Icons.history,
                title: 'Historique',
                subtitle: sessions.isEmpty
                    ? 'Ajouter une partie'
                    : '${sessions.length} partie${sessions.length > 1 ? 's' : ''}',
                accent: accent,
                selected: _tab == _PlayHubTab.history,
                onTap: () => _select(_PlayHubTab.history),
              ),
              const SizedBox(height: 8),
              DetailBentoSubTile(
                icon: Icons.insights_outlined,
                title: 'Stats',
                subtitle: sessions.isEmpty ? 'Résumé des parties' : 'Victoires & scores',
                accent: accent,
                selected: _tab == _PlayHubTab.stats,
                onTap: () => _select(_PlayHubTab.stats),
              ),
              const SizedBox(height: 8),
              DetailBentoSubTile(
                icon: Icons.emoji_events_outlined,
                title: 'Classement',
                subtitle: stats.podiumSlots.isEmpty
                    ? 'Podium & matrices'
                    : '${stats.winPodium.length} joueur${stats.winPodium.length > 1 ? 's' : ''}',
                accent: accent,
                selected: _tab == _PlayHubTab.ranking,
                onTap: () => _select(_PlayHubTab.ranking),
              ),
              if (_tab != _PlayHubTab.none) ...[
                const SizedBox(height: 12),
                switch (_tab) {
                  _PlayHubTab.history => BoardgamePlayHistoryPanel(
                      item: widget.item,
                      readOnly: widget.readOnly,
                      mode: BoardgamePlayPanelMode.history,
                      onMetadataChanged: widget.onMetadataChanged,
                    ),
                  _PlayHubTab.stats => _StatsBody(
                      sessions: sessions,
                      stats: stats,
                    ),
                  _PlayHubTab.ranking => BoardgamePlayHistoryPanel(
                      item: widget.item,
                      readOnly: widget.readOnly,
                      mode: BoardgamePlayPanelMode.ranking,
                      onMetadataChanged: widget.onMetadataChanged,
                    ),
                  _PlayHubTab.none => const SizedBox.shrink(),
                },
              ],
            ],
          ),
        ),
        if (!widget.readOnly) ...[
          const SizedBox(height: 12),
          if (widget.item.groupId != null)
            GroupRulesPanel(
              groupId: widget.item.groupId!,
              itemId: widget.item.id,
              itemTitle: widget.item.title,
              accent: accent,
            )
          else if (widget.personalRulesController != null)
            TextField(
              controller: widget.personalRulesController,
              readOnly: widget.readOnly,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Règles personnalisées',
                border: OutlineInputBorder(),
              ),
            ),
        ],
      ],
    );
  }
}

class _StatsBody extends StatelessWidget {
  final List<BoardgamePlaySession> sessions;
  final BoardgameRankingStats stats;

  const _StatsBody({required this.sessions, required this.stats});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (sessions.isEmpty) {
      return Text(
        'Joue une partie pour voir les stats.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${sessions.length} partie${sessions.length > 1 ? 's' : ''} · '
          '${stats.allPlayerNames.length} joueur${stats.allPlayerNames.length > 1 ? 's' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (stats.winPodium.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...stats.winPodium.take(5).map(
                (w) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${w.name} — ${w.wins} victoire${w.wins > 1 ? 's' : ''} '
                    '(${w.gamesPlayed} partie${w.gamesPlayed > 1 ? 's' : ''})',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
        ],
        if (stats.allScores.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Meilleur score : ${stats.allScores.first.player} '
            '(${stats.allScores.first.score})',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
