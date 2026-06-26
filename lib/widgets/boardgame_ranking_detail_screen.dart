import 'package:flutter/material.dart';

import '../models/boardgame_play_session.dart';
import '../utils/boardgame_play_stats.dart';

enum RankingDetailMode {
  scores,
  averages,
  wins,
}

/// Écran plein écran pour une vue statistique avec bascule de sens.
class BoardgameRankingDetailScreen extends StatefulWidget {
  final String title;
  final RankingDetailMode mode;
  final BoardgameRankingStats stats;
  final List<BoardgamePlaySession> sessions;
  final void Function(int sessionIndex)? onOpenSession;

  const BoardgameRankingDetailScreen({
    super.key,
    required this.title,
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
  bool _reversed = false;

  String get _flipTarget => switch (widget.mode) {
        RankingDetailMode.scores =>
          _reversed ? 'Meilleurs scores' : 'Pires scores',
        RankingDetailMode.averages =>
          _reversed ? 'Meilleures moyennes' : 'Pires moyennes',
        RankingDetailMode.wins =>
          _reversed ? 'Nombre de victoires' : 'Nombre de fois dernier',
      };

  List<BoardgameMatrixRow> get _rows {
    switch (widget.mode) {
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
        if (!_reversed) {
          return widget.stats.winsMatrixRows;
        }
        return (widget.stats.gamesPlayedByPlayer.keys.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
            .map((name) {
          final last = widget.stats.lastPlaceByPlayer[name] ?? 0;
          return BoardgameMatrixRow(
            player: name,
            gamesPlayed: widget.stats.gamesPlayedByPlayer[name] ?? 0,
            values: [last],
            sessionIndices: const [],
          );
        }).toList()
          ..sort((a, b) => b.values.first.compareTo(a.values.first));
    }
  }

  String get _valueHeader {
    if (widget.mode == RankingDetailMode.scores) {
      return _reversed ? 'Pire score' : 'Meilleur score';
    }
    if (widget.mode == RankingDetailMode.averages) {
      return _reversed ? 'Pire moyenne' : 'Meilleure moyenne';
    }
    return _reversed ? 'Fois dernier' : 'Victoires';
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _reversed ? _flipTarget : widget.title,
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                  columns: [
                    const DataColumn(label: Text('Joueur')),
                    const DataColumn(label: Text('Parties')),
                    DataColumn(label: Text(_valueHeader)),
                    for (var i = 2; i < _maxValueCols; i++)
                      DataColumn(label: Text('Score $i')),
                  ],
                  rows: rows.map((r) {
                    return DataRow(
                      cells: [
                        DataCell(Text(r.player)),
                        DataCell(Text('${r.gamesPlayed}')),
                        for (var i = 0; i < _maxValueCols - 1; i++)
                          DataCell(
                            i < r.values.length
                                ? _ScoreCell(
                                    value: widget.mode ==
                                            RankingDetailMode.averages
                                        ? (_averageFor(r.player)
                                                ?.toStringAsFixed(1) ??
                                            '${r.values[i]}')
                                        : '${r.values[i]}',
                                    onTap: widget.mode ==
                                                RankingDetailMode.scores &&
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
            ),
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
