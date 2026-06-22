import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_author_group.dart';
import '../../models/book_series.dart';
import '../../models/book_subcategory.dart';
import '../../models/book_volume.dart';
import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../../models/collection_list_filters.dart';
import '../../services/book_series_service.dart';
import '../../services/group_service.dart';
import '../../utils/book_series_focus.dart';
import '../../utils/collection_grid_layout.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/author_avatar.dart';
import '../../widgets/book_series_tile.dart';
import '../../widgets/collection_filter_bar.dart' show GroupFilterOption;
import '../../widgets/collection_item_tile.dart';
import '../../widgets/focus_filter_button.dart';
import '../book_author_detail_screen.dart';
import '../book_series_detail_screen.dart';
import '../item_detail_screen.dart';

enum _BookCollectionViewMode { bySeries, allBooks, byAuthor }

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
  _BookCollectionViewMode _viewMode = _BookCollectionViewMode.bySeries;
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
      await _service.ensureStandaloneSeriesForUnassigned();
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

  List<CollectionItem> get _visibleBooks {
    final q = _search.text.trim().toLowerCase();
    final seen = <String>{};
    final books = <CollectionItem>[];
    for (final entry in _entries) {
      if (_filterSub != null && entry.series.subcategory != _filterSub) {
        continue;
      }
      for (final item in entry.items) {
        if (!BookSeriesFocus.itemMatchesFocus(item, _focusFilters)) continue;
        if (seen.add(item.id)) books.add(item);
      }
    }
    if (q.isEmpty) {
      books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return books;
    }
    return books
        .where((b) {
          final author = (b.metadata?['author'] as String?)?.toLowerCase() ?? '';
          return b.title.toLowerCase().contains(q) || author.contains(q);
        })
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  List<BookAuthorGroup> get _visibleAuthors {
    final groups = groupBooksByAuthor(_visibleBooks);
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return groups;
    return groups
        .where((g) => g.author.toLowerCase().contains(q))
        .toList();
  }

  String get _searchHint => switch (_viewMode) {
        _BookCollectionViewMode.bySeries => 'Filtrer une série…',
        _BookCollectionViewMode.allBooks => 'Filtrer un livre…',
        _BookCollectionViewMode.byAuthor => 'Filtrer un auteur…',
      };

  IconData get _viewModeIcon => switch (_viewMode) {
        _BookCollectionViewMode.bySeries => Icons.view_module_outlined,
        _BookCollectionViewMode.allBooks => Icons.menu_book_outlined,
        _BookCollectionViewMode.byAuthor => Icons.person_outline,
      };

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
        actions: [
          PopupMenuButton<_BookCollectionViewMode>(
            icon: Icon(_viewModeIcon),
            tooltip: 'Mode d\'affichage',
            initialValue: _viewMode,
            onSelected: (mode) => setState(() => _viewMode = mode),
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: _BookCollectionViewMode.bySeries,
                child: ListTile(
                  leading: Icon(Icons.view_module_outlined),
                  title: Text('Vue par séries'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              PopupMenuItem(
                value: _BookCollectionViewMode.allBooks,
                child: ListTile(
                  leading: Icon(Icons.menu_book_outlined),
                  title: Text('Tous les livres'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              PopupMenuItem(
                value: _BookCollectionViewMode.byAuthor,
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Par auteur'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
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
                          hintText: _searchHint,
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
            else if (_viewMode == _BookCollectionViewMode.bySeries)
              _buildSeriesSliver(visible, focusActive)
            else if (_viewMode == _BookCollectionViewMode.allBooks)
              _buildAllBooksSliver(focusActive)
            else
              _buildAuthorsSliver(focusActive),
          ],
        ),
      ),
    );
  }

  Widget _buildSeriesSliver(List<_SeriesEntry> visible, bool focusActive) {
    if (visible.isEmpty) {
      return SliverFillRemaining(
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
      );
    }
    return SliverPadding(
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
    );
  }

  Future<void> _confirmDeleteBook(CollectionItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer ce livre ?'),
        content: Text('« ${item.title} » sera supprimé de ta collection.'),
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
    await _service.removeVolumeItem(item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('« ${item.title} » retiré')),
      );
      _load();
    }
  }

  Widget _buildAllBooksSliver(bool focusActive) {
    final books = _visibleBooks;
    if (books.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _entries.isEmpty
                  ? 'Aucun livre pour l\'instant.'
                  : focusActive
                      ? 'Aucun livre ne correspond à ce focus.'
                      : 'Aucun livre ne correspond.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      sliver: SliverGrid(
        gridDelegate: CollectionGridLayout.gridDelegate(
          context,
          mobileColumns: 3,
          childAspectRatio: 0.68,
          spacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = books[index];
            return CollectionItemTile(
              item: item,
              category: CollectionCategory.book,
              coverFirst: true,
              showGroupBadge: false,
              onTap: () => _openBook(item),
              onDelete: () => _confirmDeleteBook(item),
            );
          },
          childCount: books.length,
        ),
      ),
    );
  }

  Widget _buildAuthorsSliver(bool focusActive) {
    final authors = _visibleAuthors;
    if (authors.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _entries.isEmpty
                  ? 'Aucun auteur pour l\'instant.\nAjoute des livres avec métadonnées auteur.'
                  : focusActive
                      ? 'Aucun auteur ne correspond à ce focus.'
                      : 'Aucun auteur ne correspond.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final group = authors[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) =>
                        BookAuthorDetailScreen(group: group),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      AuthorAvatar(
                        authorName: group.author,
                        photoUrl: group.photoUrl,
                        radius: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              group.author,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${group.ownedCount} possédé(s) · ${group.totalCount} entrée(s)',
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
            );
          },
          childCount: authors.length,
        ),
      ),
    );
  }

  Future<void> _openBook(CollectionItem item) async {
    if (item.seriesId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => BookSeriesDetailScreen(seriesId: item.seriesId!),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => ItemDetailScreen(item: item),
        ),
      );
    }
    if (mounted) _load();
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
