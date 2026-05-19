import 'package:flutter/material.dart';

import '../models/novel_rating_matrix.dart';
import '../services/book_series_service.dart';
import '../widgets/app_app_bar.dart';

/// Grille type IMDB : saisons en colonnes, chapitres en lignes.
class NovelRatingMatrixScreen extends StatefulWidget {
  final String seriesId;

  const NovelRatingMatrixScreen({super.key, required this.seriesId});

  @override
  State<NovelRatingMatrixScreen> createState() =>
      _NovelRatingMatrixScreenState();
}

class _NovelRatingMatrixScreenState extends State<NovelRatingMatrixScreen> {
  final _service = BookSeriesService();
  bool _loading = true;
  NovelRatingMatrix _matrix = const NovelRatingMatrix();
  String _seriesName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final series = await _service.fetchSeriesById(widget.seriesId);
    if (series == null || !mounted) return;
    setState(() {
      _seriesName = series.name;
      _matrix = series.novelMatrix;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _service.saveNovelMatrix(widget.seriesId, _matrix);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Matrice enregistrée')),
      );
    }
  }

  Future<void> _editDimensions() async {
    final seasons = TextEditingController(
      text: _matrix.seasonLabels.join(', '),
    );
    final chapters = TextEditingController(
      text: _matrix.chapterLabels.join(', '),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dimensions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: seasons,
              decoration: const InputDecoration(
                labelText: 'Colonnes (saisons), séparées par des virgules',
              ),
            ),
            TextField(
              controller: chapters,
              decoration: const InputDecoration(
                labelText: 'Lignes (chapitres), séparées par des virgules',
              ),
            ),
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
    if (ok != true) return;
    setState(() {
      _matrix = _matrix.withDimensions(
        seasons: seasons.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        chapters: chapters.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
    });
    seasons.dispose();
    chapters.dispose();
  }

  Future<void> _editCell(int si, int ci) async {
    final key = NovelRatingMatrix.cellKey(si, ci);
    final current = _matrix.scores[key];
    final ctrl = TextEditingController(
      text: current?.toString() ?? '',
    );
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${_matrix.chapterLabels[ci]} · ${_matrix.seasonLabels[si]}',
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Note 0–10 (vide = N/A)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('N/A'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    setState(() {
      if (result.isEmpty) {
        _matrix = _matrix.withScore(si, ci, null);
      } else {
        _matrix = _matrix.withScore(si, ci, double.tryParse(result));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final seasons = _matrix.seasonLabels;
    final chapters = _matrix.chapterLabels;

    return Scaffold(
      appBar: AppAppBar(title: 'Notes · $_seriesName'),
      body: seasons.isEmpty || chapters.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Définis les saisons (colonnes) et chapitres (lignes).',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _editDimensions,
                      child: const Text('Configurer la grille'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _editDimensions,
                        icon: const Icon(Icons.tune),
                        label: const Text('Dimensions'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _save,
                        child: const Text('Enregistrer'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowHeight: 48,
                        columns: [
                          const DataColumn(label: Text('')),
                          for (final s in seasons) DataColumn(label: Text(s)),
                        ],
                        rows: [
                          for (var ci = 0; ci < chapters.length; ci++)
                            DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    chapters[ci],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                for (var si = 0; si < seasons.length; si++)
                                  DataCell(
                                    _ScoreCell(
                                      score: _matrix.scoreAt(si, ci),
                                      onTap: () => _editCell(si, ci),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Rouge = faible · Vert foncé = excellent · Gris = N/A',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ScoreCell extends StatelessWidget {
  final double? score;
  final VoidCallback onTap;

  const _ScoreCell({required this.score, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = score != null ? score!.toStringAsFixed(1) : 'N/A';
    final color = Color(NovelRatingMatrix.scoreColorArgb(score));
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: score != null ? Colors.white : Colors.grey.shade800,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
