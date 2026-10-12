import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/boardgame_play_session.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../utils/boardgame_display.dart';
import '../utils/boardgame_play_stats.dart';
import 'boardgame_play_history_panel.dart';
import 'group_rules_panel.dart';

enum _BentoTile { stats, infos, history, ranking }

/// Tuiles cliquables pour la fiche détail jeu de société.
class BoardgameDetailBento extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final int? bestPlayers;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;
  final TextEditingController? personalRulesController;

  const BoardgameDetailBento({
    super.key,
    required this.item,
    required this.readOnly,
    required this.onMetadataChanged,
    this.bestPlayers,
    this.personalRulesController,
  });

  @override
  State<BoardgameDetailBento> createState() => _BoardgameDetailBentoState();
}

class _BoardgameDetailBentoState extends State<BoardgameDetailBento> {
  _BentoTile? _expanded;

  List<BoardgamePlaySession> get _sessions =>
      parseBoardgamePlays(widget.item.metadata);

  void _toggle(_BentoTile tile) {
    setState(() => _expanded = _expanded == tile ? null : tile);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = Colors.orange.shade800;
    final sessions = _sessions;
    final stats = BoardgameRankingStats.fromSessions(sessions);
    final m = widget.item.metadata ?? {};

    final players = formatPlayerCount(
      widget.item.minPlayers,
      widget.item.maxPlayers,
    );
    final time = formatPlayingTime(widget.item.playingTime);
    final year = m['year_published'] ?? m['year'];
    final minAge = m['min_age'];
    final bestLabel = formatBggBestPlayersLabel(
      widget.bestPlayers ?? parseBggBestPlayers(m['bgg_best_players']),
    );

    final infoBits = <String>[
      ?players,
      ?bestLabel,
      ?time,
      if (year != null && year.toString().isNotEmpty) year.toString(),
      if (minAge != null) '$minAge+',
    ];

    final topWin = stats.winPodium.isNotEmpty ? stats.winPodium.first : null;
    final statsSubtitle = sessions.isEmpty
        ? 'Aucune partie'
        : topWin != null
            ? '${sessions.length} partie${sessions.length > 1 ? 's' : ''} · ${topWin.name} en tête'
            : '${sessions.length} partie${sessions.length > 1 ? 's' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 420;
            final tiles = [
              _BentoCard(
                icon: Icons.insights_outlined,
                title: 'Stats',
                subtitle: statsSubtitle,
                accent: accent,
                selected: _expanded == _BentoTile.stats,
                onTap: () => _toggle(_BentoTile.stats),
              ),
              _BentoCard(
                icon: Icons.info_outline,
                title: 'Infos',
                subtitle: infoBits.isEmpty
                    ? 'Fiche technique'
                    : infoBits.take(2).join(' · '),
                accent: accent,
                selected: _expanded == _BentoTile.infos,
                onTap: () => _toggle(_BentoTile.infos),
              ),
              _BentoCard(
                icon: Icons.history,
                title: 'Historique',
                subtitle: sessions.isEmpty
                    ? 'Ajouter une partie'
                    : '${sessions.length} partie${sessions.length > 1 ? 's' : ''}',
                accent: accent,
                selected: _expanded == _BentoTile.history,
                onTap: () => _toggle(_BentoTile.history),
              ),
              _BentoCard(
                icon: Icons.emoji_events_outlined,
                title: 'Classement',
                subtitle: stats.podiumSlots.isEmpty
                    ? 'Podium & scores'
                    : '${stats.winPodium.length} joueur${stats.winPodium.length > 1 ? 's' : ''}',
                accent: accent,
                selected: _expanded == _BentoTile.ranking,
                onTap: () => _toggle(_BentoTile.ranking),
              ),
            ];

            if (wide) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: tiles[0]),
                      const SizedBox(width: 10),
                      Expanded(child: tiles[1]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: tiles[2]),
                      const SizedBox(width: 10),
                      Expanded(child: tiles[3]),
                    ],
                  ),
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  tiles[i],
                ],
              ],
            );
          },
        ),
        if (_expanded != null) ...[
          const SizedBox(height: 12),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accent.withValues(alpha: 0.25),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: switch (_expanded!) {
                  _BentoTile.stats => _StatsExpanded(
                      sessions: sessions,
                      stats: stats,
                    ),
                  _BentoTile.infos => _InfosExpanded(
                      item: widget.item,
                      bestPlayersLabel: bestLabel,
                      players: players,
                      time: time,
                      year: year?.toString(),
                      minAge: minAge?.toString(),
                      accent: accent,
                    ),
                  _BentoTile.history => BoardgamePlayHistoryPanel(
                      item: widget.item,
                      readOnly: widget.readOnly,
                      mode: BoardgamePlayPanelMode.history,
                      onMetadataChanged: widget.onMetadataChanged,
                    ),
                  _BentoTile.ranking => BoardgamePlayHistoryPanel(
                      item: widget.item,
                      readOnly: widget.readOnly,
                      mode: BoardgamePlayPanelMode.ranking,
                      onMetadataChanged: widget.onMetadataChanged,
                    ),
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (!widget.readOnly) ...[
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

class _BentoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const _BentoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.14)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : scheme.outlineVariant.withValues(alpha: 0.35),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.expand_less : Icons.expand_more,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsExpanded extends StatelessWidget {
  final List<BoardgamePlaySession> sessions;
  final BoardgameRankingStats stats;

  const _StatsExpanded({required this.sessions, required this.stats});

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
          ...stats.winPodium.take(3).map(
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

class _InfosExpanded extends StatelessWidget {
  final CollectionItem item;
  final String? players;
  final String? bestPlayersLabel;
  final String? time;
  final String? year;
  final String? minAge;
  final Color accent;

  const _InfosExpanded({
    required this.item,
    required this.accent,
    this.players,
    this.bestPlayersLabel,
    this.time,
    this.year,
    this.minAge,
  });

  @override
  Widget build(BuildContext context) {
    final bggId = item.metadata?['bgg_id']?.toString();
    final bggPageUrl = BggService.gamePageUrl(bggId);
    final rows = <(IconData, String, String?)>[
      if (players != null) (Icons.people, players!, bestPlayersLabel),
      if (time != null) (Icons.timer, time!, null),
      if (year != null && year!.isNotEmpty)
        (Icons.calendar_today, year!, null),
      if (minAge != null) (Icons.child_care, '$minAge+', null),
    ];

    if (rows.isEmpty && bggPageUrl == null) {
      return Text(
        'Aucune info technique.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final row in rows)
              Chip(
                avatar: Icon(row.$1, size: 16, color: accent),
                label: Text(
                  row.$3 != null ? '${row.$2} · ${row.$3}' : row.$2,
                ),
              ),
          ],
        ),
        if (bggPageUrl != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await launchUrl(
                Uri.parse(bggPageUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Voir sur BoardGameGeek'),
          ),
        ],
      ],
    );
  }
}
