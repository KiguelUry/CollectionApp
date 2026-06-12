import 'package:flutter/material.dart';

import '../utils/book_add_actions.dart';
import '../utils/collection_grid_layout.dart';
import '../models/book_author_group.dart';
import '../models/book_series.dart';
import '../models/book_subcategory.dart';
import '../models/collection_item.dart';
import '../services/book_series_service.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/author_avatar.dart';
import '../widgets/assign_book_series_sheet.dart';
import '../widgets/book_series_tile.dart';
import 'book_author_detail_screen.dart';
import 'book_series_detail_screen.dart';
import 'item_detail_screen.dart';

enum _BookListView { series, authors }

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
  List<BookAuthorGroup> _authors = [];
  _BookListView _view = _BookListView.series;
  _SeriesSort _seriesSort = _SeriesSort.nameAz;

  @override
  void initState() {
    super.initState();
    _view = widget.subcategory == BookSubcategory.novel
        ? _BookListView.authors
        : _BookListView.series;
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
      final allBooks = await _service.fetchAllBooksInSubcategory(widget.subcategory);
      final authors = groupBooksByAuthor(allBooks);
      if (mounted) {
        setState(() {
          _series = series;
          _stats
            ..clear()
            ..addAll(statsMap);
          _unassigned = unassigned;
          _authors = authors;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: widget.subcategory.label,
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SegmentedButton<_BookListView>(
                    segments: const [
                      ButtonSegment(
                        value: _BookListView.series,
                        label: Text('Par série'),
                        icon: Icon(Icons.auto_stories_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: _BookListView.authors,
                        label: Text('Par auteur'),
                        icon: Icon(Icons.person_outline, size: 18),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) =>
                        setState(() => _view = s.first),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _view == _BookListView.authors
                        ? _buildAuthorsList()
                        : _buildSeriesList(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAuthorsList() {
    if (_authors.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucun auteur repéré.\n'
                'Ajoute des livres avec un auteur (recherche ou ISBN).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: _authors.length,
      itemBuilder: (context, i) {
        final g = _authors[i];
        return Card(
          child: ListTile(
            leading: AuthorAvatar(authorName: g.author, radius: 24),
            title: Text(g.author),
            subtitle: Text(
              '${g.ownedCount} possédé(s) · ${g.totalCount} titre(s)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => BookAuthorDetailScreen(group: g),
              ),
            ),
          ),
        );
      },
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
