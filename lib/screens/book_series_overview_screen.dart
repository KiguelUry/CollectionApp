import 'package:flutter/material.dart';

import '../models/book_series.dart';
import '../services/book_series_service.dart';
import '../widgets/app_app_bar.dart';

class BookSeriesOverviewScreen extends StatefulWidget {
  final String seriesId;

  const BookSeriesOverviewScreen({super.key, required this.seriesId});

  @override
  State<BookSeriesOverviewScreen> createState() =>
      _BookSeriesOverviewScreenState();
}

class _BookSeriesOverviewScreenState extends State<BookSeriesOverviewScreen> {
  final _service = BookSeriesService();
  final _rating = TextEditingController();
  final _review = TextEditingController();
  final _expected = TextEditingController();
  final _valueNew = TextEditingController();
  final _valueUsed = TextEditingController();
  bool _loading = true;
  BookSeries? _series;
  BookSeriesStats? _stats;

  @override
  void dispose() {
    _rating.dispose();
    _review.dispose();
    _expected.dispose();
    _valueNew.dispose();
    _valueUsed.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final series = await _service.fetchSeriesById(widget.seriesId);
    if (series == null || !mounted) return;
    final volumes = await _service.fetchVolumes(series.id);
    final items = await _service.fetchSeriesItems(series.id);
    final stats = _service.computeStats(
      series: series,
      volumes: volumes,
      items: items,
    );
    _rating.text = series.userRating?.toString() ?? '';
    _review.text = series.userReview ?? '';
    _expected.text = series.expectedVolumeCount?.toString() ?? '';
    _valueNew.text = stats.totalNewValue > 0
        ? stats.totalNewValue.toStringAsFixed(0)
        : '';
    _valueUsed.text = stats.totalUsedValue > 0
        ? stats.totalUsedValue.toStringAsFixed(0)
        : '';
    if (mounted) {
      setState(() {
        _series = series;
        _stats = stats;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final s = _series!;
    final meta = Map<String, dynamic>.from(s.metadata);
    final vn = double.tryParse(_valueNew.text.trim());
    final vu = double.tryParse(_valueUsed.text.trim());
    if (vn != null) meta['total_value_new'] = vn;
    if (vu != null) meta['total_value_used'] = vu;

    await _service.updateSeries(
      s.copyWith(
        userRating: double.tryParse(_rating.text.trim()),
        userReview: _review.text.trim().isEmpty ? null : _review.text.trim(),
        expectedVolumeCount: int.tryParse(_expected.text.trim()),
        metadata: meta,
      ),
    );
    final count = int.tryParse(_expected.text.trim());
    if (count != null && count > 0) {
      await _service.ensureVolumeSlots(s.id, count);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fiche série enregistrée')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _series == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final stats = _stats!;

    return Scaffold(
      appBar: const AppAppBar(title: 'Fiche série'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _series!.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Text('Résumé', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text('Possédé : ${stats.ownedLabel} · Lu : ${stats.readLabel}'),
          if (stats.ratingLabel != null)
            Text('Note affichée : ★ ${stats.ratingLabel}'),
          const Divider(height: 32),
          TextField(
            controller: _rating,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Ma note série (0–5)',
              hintText: '4.5',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _review,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Avis sur la série',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _expected,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nombre de tomes dans la série',
              hintText: 'Ex. 38 pour Thorgal',
              helperText:
                  'Si Open Library ne détecte pas le bon total, indique-le ici '
                  'puis enregistre : les emplacements de tomes seront créés.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valueNew,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valeur totale neuf (€)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valueUsed,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valeur totale occasion (€)',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('Enregistrer'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              await _service.recomputeSeriesValues(_series!.id);
              await _load();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Valeurs recalculées depuis les tomes'),
                  ),
                );
              }
            },
            child: const Text('Recalculer depuis les tomes possédés'),
          ),
        ],
      ),
    );
  }
}
