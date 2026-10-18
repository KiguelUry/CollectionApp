import 'package:flutter/material.dart';

import '../models/boardgame_play_session.dart';
import '../models/collection_item.dart';
import '../services/player_alias_service.dart';
import '../utils/boardgame_play_stats.dart';
import 'boardgame_play_history_panel.dart';
import 'detail_bento_tile.dart';

enum _PlayHubTab { none, history, stats, ranking }

/// Contenu du bento « Parties et classements » (sous-tuiles directes, sans hub intermédiaire).
class BoardgamePlaySectionsPanel extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;

  const BoardgamePlaySectionsPanel({
    super.key,
    required this.item,
    required this.readOnly,
    required this.onMetadataChanged,
  });

  @override
  State<BoardgamePlaySectionsPanel> createState() =>
      _BoardgamePlaySectionsPanelState();
}

class _BoardgamePlaySectionsPanelState extends State<BoardgamePlaySectionsPanel> {
  _PlayHubTab _tab = _PlayHubTab.none;

  @override
  void initState() {
    super.initState();
    PlayerAliasService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  List<BoardgamePlaySession> get _sessions =>
      parseBoardgamePlays(widget.item.metadata);

  void _select(_PlayHubTab tab) {
    setState(() => _tab = _tab == tab ? _PlayHubTab.none : tab);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Colors.orange.shade800;
    final sessions = _sessions;
    final aliases = PlayerAliasService.instance;
    final stats = BoardgameRankingStats.fromSessions(
      sessions,
      resolveName: aliases.canonical,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailBentoSubTile(
          icon: Icons.history,
          title: 'Historique & parties',
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
          title: 'Statistiques',
          subtitle: sessions.isEmpty
              ? 'Résumé des parties'
              : 'Victoires & scores',
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
    );
  }
}

/// @deprecated Utiliser [BoardgamePlaySectionsPanel] dans le bento parent.
typedef BoardgamePlayHubBento = BoardgamePlaySectionsPanel;

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
