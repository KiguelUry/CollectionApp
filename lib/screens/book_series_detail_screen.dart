import 'package:flutter/material.dart';

import '../constants/book_accent.dart';
import '../coordinators/book_item_add_coordinator.dart';
import '../models/book_series.dart';
import '../models/book_volume.dart';
import '../services/book_series_service.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/book_volume_cell.dart';
import '../widgets/book_volume_status_sheet.dart';
import '../widgets/collection_cover_image.dart';

/// Détail série : grille de tomes avec états Possédé × Lu.
class BookSeriesDetailScreen extends StatefulWidget {
  final String seriesId;

  const BookSeriesDetailScreen({super.key, required this.seriesId});

  @override
  State<BookSeriesDetailScreen> createState() => _BookSeriesDetailScreenState();
}

class _BookSeriesDetailScreenState extends State<BookSeriesDetailScreen> {
  final _service = BookSeriesService();
  bool _loading = true;
  BookSeries? _series;
  BookSeriesStats? _stats;
  List<BookVolumeSlot> _slots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final series = await _service.fetchSeriesById(widget.seriesId);
      if (series == null) throw Exception('Série introuvable');

      final volumes = await _service.fetchVolumes(series.id);
      final items = await _service.fetchSeriesItems(series.id);
      final stats = _service.computeStats(
        series: series,
        volumes: volumes,
        items: items,
      );
      final slots = _service.buildVolumeSlots(
        series: series,
        volumes: volumes,
        items: items,
      );

      if (mounted) {
        setState(() {
          _series = series;
          _stats = stats;
          _slots = slots;
          _loading = false;
        });
        _service.enrichMissingVolumeCovers(
          series: series,
          volumes: volumes,
        ).then((_) {
          if (mounted) _load();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _openVolumeSheet(BookVolumeSlot slot) async {
    final series = _series!;
    await showBookVolumeStatusSheet(
      context,
      series: series,
      slot: slot,
      service: _service,
      onChanged: _load,
    );
    await _load();
  }

  Future<void> _addVolumeFromSearch() async {
    final series = _series!;
    await BookItemAddCoordinator(context).addVolumeFromCatalog(
      seriesId: series.id,
      seriesName: series.name,
      subcategory: series.subcategory,
      expectedVolumeCount: series.expectedVolumeCount,
    );
    await _load();
  }

  Future<void> _editExpectedCount() async {
    final series = _series!;
    final controller = TextEditingController(
      text: '${series.expectedVolumeCount ?? _slots.length}',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre de tomes'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Total estimé',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, n);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == null || result < 1) return;
    await _service.ensureVolumeSlots(series.id, result);
    await _service.updateSeries(
      series.copyWith(expectedVolumeCount: result),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _series == null) {
      return Scaffold(
        appBar: AppAppBar(
          title: 'Série',
          backgroundColor: BookAccent.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final series = _series!;
    final stats = _stats!;
    final accent = BookAccent.primary;

    return Scaffold(
      appBar: AppAppBar(
        title: series.name,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Ajouter un tome',
            icon: const Icon(Icons.add),
            onPressed: _addVolumeFromSearch,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'count') await _editExpectedCount();
              if (v == 'delete') await _confirmDelete(series);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'count',
                child: Text('Ajuster le nombre de tomes'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Supprimer la série'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: accent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (series.coverUrl != null && series.coverUrl!.isNotEmpty)
                      CollectionCoverImage(
                        url: series.coverUrl!,
                        width: 72,
                        height: 104,
                        bookCover: true,
                      )
                    else
                      Container(
                        width: 72,
                        height: 104,
                        decoration: BoxDecoration(
                          color: BookAccent.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          series.subcategory.icon,
                          color: accent,
                          size: 32,
                        ),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            series.subcategory.label,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _StatChip(
                                icon: Icons.home_rounded,
                                label: 'Possédé ${stats.ownedLabel}',
                                color: accent,
                              ),
                              _StatChip(
                                icon: Icons.visibility_rounded,
                                label: 'Lu ${stats.readLabel}',
                                color: Colors.amber.shade800,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Touche un tome pour gérer Possédé et Lu.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_slots.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Aucun tome défini',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _editExpectedCount,
                        icon: const Icon(Icons.format_list_numbered),
                        label: const Text('Définir les tomes'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.58,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final slot = _slots[index];
                      return BookVolumeCell(
                        slot: slot,
                        accent: accent,
                        onTap: () => _openVolumeSheet(slot),
                      );
                    },
                    childCount: _slots.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BookSeries series) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la série ?'),
        content: Text(
          '« ${series.name} » sera retirée. Les livres restent en collection '
          'mais ne seront plus liés à cette série.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.deleteSeries(series.id);
    if (mounted) Navigator.pop(context);
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
