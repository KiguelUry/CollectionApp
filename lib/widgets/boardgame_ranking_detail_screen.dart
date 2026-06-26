import 'package:flutter/material.dart';

import '../models/boardgame_play_session.dart';
import '../utils/boardgame_play_stats.dart';

enum RankingDetailMode {
  global,
  scores,
  averages,
  wins,
}

/// Écran plein écran pour une vue statistique avec bascule de type.
class BoardgameRankingDetailScreen extends StatefulWidget {
  final RankingDetailMode mode;
  final BoardgameRankingStats stats;
  final List<BoardgamePlaySession> sessions;
  final void Function(int sessionIndex)? onOpenSession;

  const BoardgameRankingDetailScreen({
    super.key,
    required this.mode,
    required this.stats,
    required this.sessions,
    this.onOpenSession,
  });

  @override
  State<BoardgameRankingDetailScreen> createState() =>
      _BoardgameRankingDetailScreenState();
}

class _BoardgameRankingDetailScreenState
    extends State<BoardgameRankingDetailScreen> {
  late RankingDetailMode _mode;
  bool _reversed = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
  }

  bool get _canReverse =>
      _mode == RankingDetailMode.scores ||
      _mode == RankingDetailMode.averages;

  String get _title => switch (_mode) {
        RankingDetailMode.global => 'Vue globale des parties',
        RankingDetailMode.scores => 'Meilleurs scores',
        RankingDetailMode.averages => 'Meilleures moyennes',
        RankingDetailMode.wins => 'Nombre de victoires',
      };

  String get _flipTarget => switch (_mode) {
        RankingDetailMode.scores =>
          _reversed ? 'Meilleurs scores' : 'Pires scores',
        RankingDetailMode.averages =>
          _reversed ? 'Meilleures moyennes' : 'Pires moyennes',
        _ => _title,
      };

  List<BoardgameMatrixRow> get _rows {
    switch (_mode) {
      case RankingDetailMode.scores:
        final rows = widget.stats.scoreMatrixRows.map((r) {
          final values = List<int>.from(r.values);
          final indices = List<int>.from(r.sessionIndices);
          if (_reversed) {
            final pairs = List.generate(
              values.length,
              (i) => (values[i], indices[i]),
            )..sort((a, b) => a.$1.compareTo(b.$1));
            return BoardgameMatrixRow(
              player: r.player,
              gamesPlayed: r.gamesPlayed,
              values: pairs.map((p) => p.$1).toList(),
              sessionIndices: pairs.map((p) => p.$2).toList(),
            );
          }
          return BoardgameMatrixRow(
            player: r.player,
            gamesPlayed: r.gamesPlayed,
            values: values,
            sessionIndices: indices,
          );
        }).toList();
        if (_reversed) {
          rows.sort((a, b) {
            final av = a.values.isEmpty ? 1 << 30 : a.values.first;
            final bv = b.values.isEmpty ? 1 << 30 : b.values.first;
            return av.compareTo(bv);
          });
        }
        return rows;

      case RankingDetailMode.averages:
        final rows =
            List<BoardgameMatrixRow>.from(widget.stats.averageMatrixRows);
        if (_reversed) {
          rows.sort((a, b) => a.values.first.compareTo(b.values.first));
        }
        return rows;

      case RankingDetailMode.wins:
        return widget.stats.winsMatrixRows;

      case RankingDetailMode.global:
        return [];
    }
  }

  String _valueHeaderFor(int colIndex) {
    if (colIndex == 0) {
      if (_mode == RankingDetailMode.scores) {
        return _reversed ? 'Pire score' : 'Meilleur score';
      }
      if (_mode == RankingDetailMode.averages) {
        return _reversed ? 'Pire moyenne' : 'Meilleure moyenne';
      }
      return 'Victoires';
    }
    return 'Score ${colIndex + 1}';
  }

  double? _averageFor(String player) {
    for (final a in widget.stats.allAverages) {
      if (a.player == player) return a.average;
    }
    return null;
  }

  int get _maxValueCols {
    var m = 1;
    for (final r in _rows) {
      if (r.values.length > m) m = r.values.length;
    }
    return m.clamp(1, 12);
  }

  String _medalEmoji(int? rank) => switch (rank) {
        1 => '🥇',
        2 => '🥈',
        3 => '🥉',
        _ => '',
      };

  Widget _buildGlobalTable(ColorScheme scheme) {
    final matrix = widget.stats.globalMatrix;
    if (matrix.players.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Aucune partie avec scores enregistrés.'),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          columns: [
            const DataColumn(label: Text('Joueur')),
            ...matrix.sessionLabels.map((l) => DataColumn(label: Text(l))),
          ],
          rows: matrix.players.map((player) {
            final scores = matrix.scoresByPlayer[player] ?? [];
            return DataRow(
              cells: [
                DataCell(Text(player)),
                for (var col = 0; col < matrix.sessionIndices.length; col++)
                  DataCell(
                    col < scores.length && scores[col] != null
                        ? _GlobalScoreCell(
                            score: scores[col]!,
                            medal: _medalEmoji(
                              matrix.medalFor(
                                player,
                                matrix.sessionIndices[col],
                              ),
                            ),
                            onTap: widget.onOpenSession != null
                                ? () => widget.onOpenSession!(
                                      matrix.sessionIndices[col],
                                    )
                                : null,
                          )
                        : const Text('—'),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStandardTable(ColorScheme scheme) {
    final rows = _rows;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          columns: [
            const DataColumn(label: Text('Joueur')),
            const DataColumn(label: Text('Parties')),
            for (var i = 0; i < _maxValueCols; i++)
              DataColumn(label: Text(_valueHeaderFor(i))),
          ],
          rows: rows.map((r) {
            return DataRow(
              cells: [
                DataCell(Text(r.player)),
                DataCell(Text('${r.gamesPlayed}')),
                for (var i = 0; i < _maxValueCols; i++)
                  DataCell(
                    i < r.values.length
                        ? _ScoreCell(
                            value: _mode == RankingDetailMode.averages
                                ? (_averageFor(r.player)?.toStringAsFixed(1) ??
                                    '${r.values[i]}')
                                : '${r.values[i]}',
                            onTap: _mode == RankingDetailMode.scores &&
                                    i < r.sessionIndices.length &&
                                    widget.onOpenSession != null
                                ? () => widget.onOpenSession!(
                                      r.sessionIndices[i],
                                    )
                                : null,
                          )
                        : const Text('—'),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<RankingDetailMode>(
                segments: const [
                  ButtonSegment(
                    value: RankingDetailMode.global,
                    label: Text('Global'),
                    icon: Icon(Icons.grid_on_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: RankingDetailMode.scores,
                    label: Text('Scores'),
                    icon: Icon(Icons.leaderboard_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: RankingDetailMode.averages,
                    label: Text('Moyennes'),
                    icon: Icon(Icons.functions_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: RankingDetailMode.wins,
                    label: Text('Victoires'),
                    icon: Icon(Icons.emoji_events_outlined, size: 18),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  setState(() {
                    _mode = s.first;
                    _reversed = false;
                  });
                },
              ),
            ),
          ),
          if (_canReverse)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _reversed ? _flipTarget : _title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _reversed = !_reversed),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Changement de sens'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _mode == RankingDetailMode.global
                ? _buildGlobalTable(scheme)
                : _buildStandardTable(scheme),
          ),
        ],
      ),
    );
  }
}

class _ScoreCell extends StatelessWidget {
  final String value;
  final VoidCallback? onTap;

  const _ScoreCell({required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return Text(value);
    return InkWell(
      onTap: onTap,
      child: Text(
        value,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class _GlobalScoreCell extends StatelessWidget {
  final int score;
  final String medal;
  final VoidCallback? onTap;

  const _GlobalScoreCell({
    required this.score,
    required this.medal,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (medal.isNotEmpty) ...[
          Text(medal, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 2),
        ],
        Text(
          '$score',
          style: TextStyle(
            color: onTap != null
                ? Theme.of(context).colorScheme.primary
                : null,
            fontWeight: onTap != null ? FontWeight.w600 : null,
            decoration:
                onTap != null ? TextDecoration.underline : null,
          ),
        ),
      ],
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, child: child);
  }
}
