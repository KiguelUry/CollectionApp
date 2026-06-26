import 'package:flutter/material.dart';

import '../models/boardgame_play_session.dart';
import '../utils/boardgame_play_stats.dart';
import 'boardgame_ranking_detail_screen.dart';

/// Classement, podium et statistiques matricielles pour un jeu.
class BoardgameRankingPanel extends StatelessWidget {
  final List<BoardgamePlaySession> sessions;
  final void Function(int sessionIndex)? onOpenSession;

  const BoardgameRankingPanel({
    super.key,
    required this.sessions,
    this.onOpenSession,
  });

  void _openDetail(
    BuildContext context,
    RankingDetailMode mode,
    String title,
    BoardgameRankingStats stats,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BoardgameRankingDetailScreen(
          title: title,
          mode: mode,
          stats: stats,
          sessions: sessions,
          onOpenSession: onOpenSession,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = BoardgameRankingStats.fromSessions(sessions);
    final scheme = Theme.of(context).colorScheme;

    if (sessions.isEmpty) {
      return Text(
        'Joue quelques parties pour voir le classement.',
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stats.winPodium.isNotEmpty) ...[
          Text(
            'Podium',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          _PodiumRow(top: stats.winPodium.take(3).toList()),
          const SizedBox(height: 16),
        ],
        if (stats.topDuos.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Duos de choc',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                ...stats.topDuos.take(3).map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${d.label} — ${d.winsTogether} victoire${d.winsTogether > 1 ? 's' : ''} ensemble',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _StatBlock(
          title: 'Meilleurs scores',
          subtitle: 'Tape pour voir toute la liste',
          children: stats.allScores.take(5).map((s) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${s.player} — ${s.score} pts',
                style: const TextStyle(fontSize: 13),
              ),
            );
          }),
          onTap: () => _openDetail(
            context,
            RankingDetailMode.scores,
            'Meilleurs scores',
            stats,
          ),
        ),
        const SizedBox(height: 12),
        _StatBlock(
          title: 'Meilleures moyennes',
          subtitle: 'Tape pour voir toute la liste',
          children: stats.allAverages.take(5).map((a) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${a.player} — ${a.average.toStringAsFixed(1)} pts (${a.games} partie${a.games > 1 ? 's' : ''})',
                style: const TextStyle(fontSize: 13),
              ),
            );
          }),
          onTap: () => _openDetail(
            context,
            RankingDetailMode.averages,
            'Meilleures moyennes',
            stats,
          ),
        ),
        const SizedBox(height: 12),
        _StatBlock(
          title: 'Nombre de victoires',
          subtitle: 'Tape pour voir toute la liste',
          children: stats.winPodium.take(5).map((w) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${w.name} — ${w.wins} victoire${w.wins > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
            );
          }),
          onTap: () => _openDetail(
            context,
            RankingDetailMode.wins,
            'Nombre de victoires',
            stats,
          ),
        ),
      ],
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String title;
  final String subtitle;
  final Iterable<Widget> children;
  final VoidCallback onTap;

  const _StatBlock({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = children.toList();
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(Icons.open_in_full, size: 16, color: scheme.primary),
                ],
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              if (list.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...list,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PodiumRow extends StatelessWidget {
  final List<BoardgameWinHighlight> top;

  const _PodiumRow({required this.top});

  @override
  Widget build(BuildContext context) {
    if (top.isEmpty) return const SizedBox.shrink();
    final ordered = <BoardgameWinHighlight?>[
      if (top.length > 1) top[1],
      top[0],
      if (top.length > 2) top[2],
    ];
    final heights = [72.0, 96.0, 56.0];
    final medals = [
      Colors.grey.shade400,
      Colors.amber.shade600,
      Colors.brown.shade400,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(ordered.length, (i) {
        final e = ordered[i];
        if (e == null) return const SizedBox(width: 80);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events, color: medals[i], size: 22),
              const SizedBox(height: 4),
              Container(
                width: 76,
                height: heights[i],
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: medals[i].withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  border: Border.all(color: medals[i].withValues(alpha: 0.6)),
                ),
                child: Text(
                  '${e.wins}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 80,
                child: Text(
                  e.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
