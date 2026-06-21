import 'package:flutter/material.dart';

import '../utils/book_add_actions.dart';
import '../utils/collection_grid_layout.dart';
import '../models/book_series.dart';
import '../models/book_subcategory.dart';
import '../models/collection_item.dart';
import '../services/book_series_service.dart';
import '../constants/book_accent.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/assign_book_series_sheet.dart';
import '../widgets/book_series_tile.dart';
import 'book_series_detail_screen.dart';
import 'item_detail_screen.dart';

enum _SeriesSort { nameAz, ownedDesc }

class BookSubcategorySeriesScreen extends StatefulWidget {
  final BookSubcategory subcategory;

  const BookSubcategorySeriesScreen({super.key, required this.subcategory});

  @override
  State<BookSubcategorySeriesScreen> createState() =>
      _BookSubcategorySeriesScreenState();
}

class _BookSubcategorySeriesScreenState
    extends State<BookSubcategorySeriesScreen> {
  final _service = BookSeriesService();
  bool _loading = true;
  List<BookSeries> _series = [];
  final Map<String, BookSeriesStats> _stats = {};
  List<CollectionItem> _unassigned = [];
  _SeriesSort _seriesSort = _SeriesSort.nameAz;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final series = await _service.fetchSeries(
        subcategory: widget.subcategory,
        rootsOnly: true,
      );
      final statsMap = <String, BookSeriesStats>{};
      for (final s in series) {
        final volumes = await _service.fetchVolumes(s.id);
        final items = await _service.fetchSeriesItems(s.id);
        statsMap[s.id] = _service.computeStats(
          series: s,
          volumes: volumes,
          items: items,
        );
      }
      final unassigned = await _service.fetchUnassignedBooks(widget.subcategory);
      if (mounted) {
        setState(() {
          _series = series;
          _stats
            ..clear()
            ..addAll(statsMap);
          _unassigned = unassigned;
          _loading = false;
        });
        _applySeriesSort();
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

  void _applySeriesSort() {
    setState(() {
      switch (_seriesSort) {
        case _SeriesSort.nameAz:
          _series.sort((a, b) => a.name.compareTo(b.name));
        case _SeriesSort.ownedDesc:
          _series.sort(
            (a, b) => (_stats[b.id]?.ownedCount ?? 0)
                .compareTo(_stats[a.id]?.ownedCount ?? 0),
          );
      }
    });
  }

  void _openSeries(BookSeries series) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => BookSeriesDetailScreen(seriesId: series.id),
      ),
    ).then((_) => _load());
  }

  Future<void> _confirmDeleteSeries(BookSeries series) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la série ?'),
        content: Text('« ${series.name} » sera retirée de ta liste.'),
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
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: widget.subcategory.label,
        backgroundColor: BookAccent.primary,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Tri',
            onSelected: (value) {
              if (value == 'name') {
                setState(() => _seriesSort = _SeriesSort.nameAz);
                _applySeriesSort();
              } else if (value == 'owned') {
                setState(() => _seriesSort = _SeriesSort.ownedDesc);
                _applySeriesSort();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'name', child: Text('Séries A → Z')),
              PopupMenuItem(
                value: 'owned',
                child: Text('Séries · plus possédées'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openBookAddFlow(
          context,
          subcategory: widget.subcategory,
        ).then((_) => _load()),
        tooltip: 'Ajouter série ou livre',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: BookAccent.primary,
              child: _buildSeriesList(),
            ),
    );
  }

  Widget _buildSeriesList() {
    return CustomScrollView(
                slivers: [
                  if (_series.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Aucune série ${widget.subcategory.label.toLowerCase()}.\n'
                            'Crée « Naruto », « Thorgal »… avec le bouton +',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      sliver: SliverGrid(
                        gridDelegate: CollectionGridLayout.gridDelegate(
                          context,
                          mobileColumns: 2,
                          childAspectRatio: 0.92,
                          spacing: 10,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final s = _series[i];
                            return BookSeriesTile(
                              series: s,
                              stats: _stats[s.id] ?? const BookSeriesStats(),
                              accent: BookAccent.primary,
                              onDelete: () => _confirmDeleteSeries(s),
                              onTap: () => _openSeries(s),
                            );
                          },
                          childCount: _series.length,
                        ),
                      ),
                    ),
                  if (_unassigned.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                        child: Text(
                          'Sans série',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final item = _unassigned[i];
                          return ListTile(
                            title: Text(item.title),
                            subtitle: Text(item.listSubtitle ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.link),
                              tooltip: 'Rattacher à une série',
                              onPressed: () async {
                                final ok = await showAssignBookToSeriesSheet(
                                  context,
                                  item: item,
                                  subcategory: widget.subcategory,
                                );
                                if (ok == true) _load();
                              },
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) =>
                                    ItemDetailScreen(item: item),
                              ),
                            ).then((_) => _load()),
                          );
                        },
                        childCount: _unassigned.length,
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 88)),
                ],
    );
  }
}
