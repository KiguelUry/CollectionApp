import 'package:flutter/material.dart';

import '../models/boardgame_play_session.dart';
import '../utils/boardgame_play_stats.dart';
import 'boardgame_ranking_detail_screen.dart';

String _rankEmoji(int index) {
  return switch (index) {
    0 => '🥇',
    1 => '🥈',
    2 => '🥉',
    3 => '🍫',
    _ => '',
  };
}

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
    BoardgameRankingStats stats,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BoardgameRankingDetailScreen(
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
        if (stats.podiumSlots.isNotEmpty) ...[
          Text(
            'Podium',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          _PodiumRow(slots: stats.podiumSlots),
          const SizedBox(height: 8),
          ...stats.winPodium.take(5).toList().asMap().entries.map((e) {
            final w = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_rankEmoji(e.key)} ${w.name} — ${w.wins} victoire${w.wins > 1 ? 's' : ''} · ${w.gamesPlayed} partie${w.gamesPlayed > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            );
          }),
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
          title: 'Vue globale des parties',
          subtitle: 'Matrice joueurs × parties — tape pour agrandir',
          children: [
            Text(
              '${stats.globalMatrix.players.length} joueur(s) · ${stats.globalMatrix.sessionLabels.length} partie(s)',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          onTap: () => _openDetail(
            context,
            RankingDetailMode.global,
            stats,
          ),
        ),
        const SizedBox(height: 12),
        _StatBlock(
          title: 'Meilleurs scores',
          subtitle: 'Tape pour voir toute la liste',
          children: stats.allScores.take(5).toList().asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_rankEmoji(e.key)} ${e.value.player} — ${e.value.score} pts',
                style: const TextStyle(fontSize: 13),
              ),
            );
          }),
          onTap: () => _openDetail(
            context,
            RankingDetailMode.scores,
            stats,
          ),
        ),
        const SizedBox(height: 12),
        _StatBlock(
          title: 'Meilleures moyennes',
          subtitle: 'Tape pour voir toute la liste',
          children: stats.allAverages.take(5).toList().asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_rankEmoji(e.key)} ${e.value.player} — ${e.value.average.toStringAsFixed(1)} pts (${e.value.games} partie${e.value.games > 1 ? 's' : ''})',
                style: const TextStyle(fontSize: 13),
              ),
            );
          }),
          onTap: () => _openDetail(
            context,
            RankingDetailMode.averages,
            stats,
          ),
        ),
        const SizedBox(height: 12),
        _StatBlock(
          title: 'Nombre de victoires',
          subtitle: 'Tape pour voir toute la liste',
          children: stats.winPodium.take(5).toList().asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_rankEmoji(e.key)} ${e.value.name} — ${e.value.wins} victoire${e.value.wins > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
            );
          }),
          onTap: () => _openDetail(
            context,
            RankingDetailMode.wins,
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
  final List<BoardgamePodiumSlot> slots;

  const _PodiumRow({required this.slots});

  Color _medalColor(int rank) => switch (rank) {
        1 => const Color(0xFFFFD700),
        2 => const Color(0xFFC0C0C0),
        3 => const Color(0xFFCD7F32),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    BoardgamePodiumSlot? slotFor(int rank) {
      for (final s in slots) {
        if (s.rank == rank) return s;
      }
      return null;
    }

    final silver = slotFor(2);
    final gold = slotFor(1);
    final bronze = slotFor(3);

    Widget buildSlot(BoardgamePodiumSlot slot) {
      final medal = _medalColor(slot.rank);
      final height = slot.rank == 1 ? 96.0 : slot.rank == 2 ? 72.0 : 56.0;
      final width = slot.players.length > 1 ? 120.0 : 76.0;
      final names = slot.players.map((p) => p.name).join(' & ');
      final wins = slot.players.first.wins;
      final games = slot.players.first.gamesPlayed;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events, color: medal, size: 22),
            const SizedBox(height: 4),
            Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: medal.withValues(alpha: 0.25),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                border: Border.all(color: medal.withValues(alpha: 0.6)),
              ),
              child: Text(
                '$wins',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: width + 8,
              child: Text(
                names,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$games partie${games > 1 ? 's' : ''}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (silver != null) buildSlot(silver) else const SizedBox(width: 88),
        if (gold != null) buildSlot(gold) else const SizedBox(width: 88),
        if (bronze != null) buildSlot(bronze) else const SizedBox(width: 88),
      ],
    );
  }
}
