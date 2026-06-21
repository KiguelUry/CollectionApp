import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_series.dart';
import '../../models/book_subcategory.dart';
import '../../models/book_volume.dart';
import '../../models/collection_item.dart';
import '../../models/collection_list_filters.dart';
import '../../services/book_series_service.dart';
import '../../services/group_service.dart';
import '../../utils/book_series_focus.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/book_series_tile.dart';
import '../../widgets/collection_filter_bar.dart' show GroupFilterOption;
import '../../widgets/focus_filter_button.dart';
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
  CollectionListFilters _focusFilters = CollectionListFilters();
  Map<String, String> _groupNamesById = {};
  List<_SeriesEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await GroupService().fetchMyGroups();
      if (mounted) {
        setState(() {
          _groupNamesById = {for (final g in groups) g.id: g.name};
        });
      }
    } catch (_) {}
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
        entries.add(
          _SeriesEntry(
            series: series,
            volumes: volumes,
            stats: stats,
            items: items,
          ),
        );
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

  BookSeriesStats _displayStats(_SeriesEntry entry) {
    if (!BookSeriesFocus.scopeIsActive(_focusFilters)) return entry.stats;
    final scoped = BookSeriesFocus.filterItems(entry.items, _focusFilters);
    return _service.computeStats(
      series: entry.series,
      volumes: entry.volumes,
      items: scoped,
    );
  }

  List<_SeriesEntry> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _entries.where((e) {
      if (_filterSub != null && e.series.subcategory != _filterSub) {
        return false;
      }
      if (!BookSeriesFocus.seriesMatchesFocus(e.items, _focusFilters)) {
        return false;
      }
      if (q.isEmpty) return true;
      return e.series.name.toLowerCase().contains(q);
    }).toList();
  }

  List<GroupFilterOption> get _groupOptions => _groupNamesById.entries
      .map((e) => GroupFilterOption(id: e.key, label: e.value))
      .toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  Future<void> _confirmDeleteSeries(BookSeries series) async {
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('« ${series.name} » supprimée')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final focusActive = BookSeriesFocus.scopeIsActive(_focusFilters);

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
                child: Row(
                  children: [
                    Expanded(
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
                    FocusFilterButton(
                      filters: _focusFilters,
                      groupOptions: _groupOptions,
                      activeColor: BookAccent.primary,
                      onChanged: (f) => setState(() => _focusFilters = f),
                    ),
                  ],
                ),
              ),
            ),
            if (focusActive)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Compteurs filtrés selon le focus sélectionné.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
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
                          : focusActive
                              ? 'Aucune série ne correspond à ce focus.'
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
                        stats: _displayStats(entry),
                        accent: BookAccent.primary,
                        onDelete: () => _confirmDeleteSeries(entry.series),
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
  final List<BookVolume> volumes;
  final BookSeriesStats stats;
  final List<CollectionItem> items;

  const _SeriesEntry({
    required this.series,
    required this.volumes,
    required this.stats,
    required this.items,
  });
}
