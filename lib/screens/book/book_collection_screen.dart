import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_subcategory.dart';
import '../../models/book_series.dart';
import '../../services/book_series_service.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/book_series_tile.dart';
import '../book_series_detail_screen.dart';

/// Collection Livres regroupée par série / œuvre.
class BookCollectionScreen extends StatefulWidget {
  const BookCollectionScreen({super.key});

  @override
  State<BookCollectionScreen> createState() => _BookCollectionScreenState();
}

class _BookCollectionScreenState extends State<BookCollectionScreen> {
  final _service = BookSeriesService();
  final _search = TextEditingController();
  bool _loading = true;
  BookSubcategory? _filterSub;
  List<_SeriesEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final seriesList = await _service.fetchAllRootSeries();
      final entries = <_SeriesEntry>[];
      for (final series in seriesList) {
        final volumes = await _service.fetchVolumes(series.id);
        final items = await _service.fetchSeriesItems(series.id);
        final stats = _service.computeStats(
          series: series,
          volumes: volumes,
          items: items,
        );
        entries.add(_SeriesEntry(series: series, stats: stats));
      }
      entries.sort(
        (a, b) => a.series.name.toLowerCase().compareTo(
              b.series.name.toLowerCase(),
            ),
      );
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
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

  List<_SeriesEntry> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _entries.where((e) {
      if (_filterSub != null && e.series.subcategory != _filterSub) {
        return false;
      }
      if (q.isEmpty) return true;
      return e.series.name.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppAppBar(
        title: 'Ma collection',
        backgroundColor: BookAccent.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: BookAccent.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Filtrer une série…',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _search.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Tout'),
                      selected: _filterSub == null,
                      selectedColor: BookAccent.surface,
                      onSelected: (_) => setState(() => _filterSub = null),
                    ),
                    const SizedBox(width: 8),
                    for (final sub in BookSubcategory.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(sub.label),
                          selected: _filterSub == sub,
                          selectedColor: BookAccent.surface,
                          onSelected: (_) =>
                              setState(() => _filterSub = sub),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _entries.isEmpty
                          ? 'Aucune série pour l\'instant.\nRecherche un livre pour en créer une.'
                          : 'Aucune série ne correspond.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final entry = visible[index];
                      return BookSeriesTile(
                        series: entry.series,
                        stats: entry.stats,
                        accent: BookAccent.primary,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => BookSeriesDetailScreen(
                                seriesId: entry.series.id,
                              ),
                            ),
                          );
                          if (mounted) _load();
                        },
                      );
                    },
                    childCount: visible.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeriesEntry {
  final BookSeries series;
  final BookSeriesStats stats;

  const _SeriesEntry({required this.series, required this.stats});
}
