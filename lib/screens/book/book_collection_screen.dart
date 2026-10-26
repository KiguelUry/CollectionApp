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
import '../../services/books_collection_cache.dart';
import '../../services/books_migration_service.dart';
import '../../services/group_service.dart';
import '../../utils/book_series_focus.dart';
import '../../utils/collection_grid_layout.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/author_avatar.dart';
import '../../widgets/book_series_tile.dart';
import '../../widgets/collection_cover_image.dart';
import '../../widgets/collection_filter_bar.dart' show GroupFilterOption;
import '../../widgets/collection_item_tile.dart';
import '../../widgets/focus_filter_button.dart';
import '../book_author_detail_screen.dart';
import '../book_series_detail_screen.dart';
import '../item_detail_screen.dart';

enum _BookCollectionViewMode { bySeries, allBooks, byAuthor }

enum _BookLayoutMode { grid, list }

enum _BookSeriesSort { alpha, progress, rating, recent }

/// Collection Livres regroupée par série / œuvre.
class BookCollectionScreen extends StatefulWidget {
  /// `true` quand embarqué dans [BooksCollectionScreen] (sans AppBar propre).
  final bool embedded;

  /// Mode wishlist : n'affiche que les séries / tomes en wishlist.
  final bool wishlistOnly;

  const BookCollectionScreen({
    super.key,
    this.embedded = false,
    this.wishlistOnly = false,
  });

  @override
  State<BookCollectionScreen> createState() => _BookCollectionScreenState();
}

class _BookCollectionScreenState extends State<BookCollectionScreen> {
  final _service = BookSeriesService();
  final _cache = BooksCollectionCache.instance;
  final _search = TextEditingController();
  bool _loading = true;
  BookSubcategory? _filterSub;
  _BookCollectionViewMode _viewMode = _BookCollectionViewMode.bySeries;
  _BookLayoutMode _layout = _BookLayoutMode.grid;
  _BookSeriesSort _sort = _BookSeriesSort.alpha;
  CollectionListFilters _focusFilters = CollectionListFilters();
  Map<String, String> _groupNamesById = {};
  List<_SeriesEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
    // Affiche le cache immédiatement si dispo, puis refresh silencieux.
    final cached = _cache.entries;
    if (cached != null && cached.isNotEmpty) {
      _entries = cached
          .map(
            (e) => _SeriesEntry(
              series: e.series,
              volumes: e.volumes,
              stats: e.stats,
              items: e.items,
            ),
          )
          .toList();
      _loading = false;
      _load(silent: true);
    } else {
      _load();
    }
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

  Future<void> _load({bool silent = false}) async {
    // N'affiche le spinner que s'il n'y a rien à montrer.
    if (!silent && _entries.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      // Migration en arrière-plan — ne bloque jamais le premier paint.
      // ignore: unawaited_futures
      BooksMigrationService.runIfNeeded();

      final bundle = await _service.fetchCollectionBundle();
      final entries = <_SeriesEntry>[];
      for (final series in bundle.series) {
        final volumes = bundle.volumesBySeries[series.id] ?? const [];
        final items = bundle.itemsBySeries[series.id] ?? const [];
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
      _cache.put([
        for (final e in entries)
          CachedSeriesEntry(
            series: e.series,
            volumes: e.volumes,
            items: e.items,
            stats: e.stats,
          ),
      ]);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
      // Enrichissements réseau non-bloquants (couvertures + faux one-shots).
      Future(() async {
        var any = false;
        final undercounted = entries
            .where(
              (e) =>
                  !e.series.isStandalone &&
                  (e.series.expectedVolumeCount ?? e.stats.totalSlots) <= 1 &&
                  (e.series.subcategory == BookSubcategory.manga ||
                      e.series.subcategory == BookSubcategory.comic ||
                      e.series.subcategory == BookSubcategory.comics ||
                      e.series.name.toLowerCase().contains('dungeon crawler')),
            )
            .take(4)
            .toList();
        for (final e in undercounted) {
          final before = e.series.expectedVolumeCount;
          final updated = await _service.ensureRealisticVolumeCount(e.series);
          if (updated.expectedVolumeCount != before) any = true;
        }
        final needCover = entries
            .where(
              (e) =>
                  e.series.coverUrl == null || e.series.coverUrl!.isEmpty,
            )
            .take(3)
            .toList();
        for (final e in needCover) {
          final n = await _service.enrichMissingVolumeCovers(
            series: e.series,
            volumes: e.volumes,
            maxLookups: 2,
          );
          if (n > 0) any = true;
        }
        if (any && mounted) _load(silent: true);
      });
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

  Widget _booksFilterChip({
    required String label,
    String? emoji,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final fg = selected ? Colors.white : null;
    return FilterChip(
      avatar: emoji != null
          ? Text(emoji, style: TextStyle(color: fg, fontSize: 14))
          : null,
      label: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      selected: selected,
      selectedColor: BookAccent.primary,
      checkmarkColor: Colors.white,
      showCheckmark: false,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: EdgeInsets.only(left: emoji != null ? 2 : 8, right: 8),
      side: BorderSide(
        color: selected
            ? BookAccent.primary
            : Theme.of(context).colorScheme.outlineVariant,
      ),
      onSelected: (_) => onTap(),
    );
  }

  List<_SeriesEntry> get _visible {
    final q = _search.text.trim().toLowerCase();
    final list = _entries.where((e) {
      if (widget.wishlistOnly) {
        final hasWish = e.items.any((i) => i.isWishlist) ||
            e.series.wishlistEntireSeries;
        if (!hasWish) return false;
      }
      if (_filterSub != null && e.series.subcategory != _filterSub) {
        return false;
      }
      if (!BookSeriesFocus.seriesMatchesFocus(e.items, _focusFilters)) {
        return false;
      }
      if (q.isEmpty) return true;
      return e.series.name.toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      switch (_sort) {
        case _BookSeriesSort.alpha:
          return a.series.name
              .toLowerCase()
              .compareTo(b.series.name.toLowerCase());
        case _BookSeriesSort.progress:
          return b.stats.ownedProgress.compareTo(a.stats.ownedProgress);
        case _BookSeriesSort.rating:
          final ar = a.stats.displayRating ?? -1;
          final br = b.stats.displayRating ?? -1;
          return br.compareTo(ar);
        case _BookSeriesSort.recent:
          final at = a.series.updatedAt ?? a.series.createdAt;
          final bt = b.series.updatedAt ?? b.series.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
      }
    });
    return list;
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

  Widget _layoutToggle() {
    return IconButton(
      tooltip: _layout == _BookLayoutMode.grid ? 'Vue liste' : 'Vue grille',
      icon: Icon(
        _layout == _BookLayoutMode.grid
            ? Icons.view_list_outlined
            : Icons.grid_view_outlined,
      ),
      onPressed: () => setState(() {
        _layout = _layout == _BookLayoutMode.grid
            ? _BookLayoutMode.list
            : _BookLayoutMode.grid;
        _viewMode = _BookCollectionViewMode.bySeries;
      }),
    );
  }

  Widget _sortMenu() {
    return PopupMenuButton<_BookSeriesSort>(
      icon: const Icon(Icons.sort, size: 22),
      tooltip: 'Trier',
      initialValue: _sort,
      onSelected: (s) => setState(() => _sort = s),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _BookSeriesSort.alpha,
          child: Text('Alphabétique'),
        ),
        PopupMenuItem(
          value: _BookSeriesSort.progress,
          child: Text('Progression'),
        ),
        PopupMenuItem(
          value: _BookSeriesSort.rating,
          child: Text('Note'),
        ),
        PopupMenuItem(
          value: _BookSeriesSort.recent,
          child: Text('Récemment modifié'),
        ),
      ],
    );
  }

  Widget _viewModeMenu() {
    return PopupMenuButton<_BookCollectionViewMode>(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final focusActive = BookSeriesFocus.scopeIsActive(_focusFilters);

    final body = RefreshIndicator(
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
                          hintText:
                              'Rechercher une série, un livre, un auteur…',
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
                    if (_viewMode == _BookCollectionViewMode.bySeries)
                      _sortMenu(),
                    _layoutToggle(),
                    if (widget.embedded) _viewModeMenu(),
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
                    _booksFilterChip(
                      label: 'Tous',
                      selected: _filterSub == null,
                      onTap: () => setState(() => _filterSub = null),
                    ),
                    const SizedBox(width: 8),
                    for (final sub in BookSubcategory.filterChips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _booksFilterChip(
                          label: sub.label,
                          emoji: sub.filterEmoji,
                          selected: _filterSub == sub,
                          onTap: () => setState(() => _filterSub = sub),
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
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppAppBar(
        title: 'Ma collection',
        backgroundColor: BookAccent.primary,
        foregroundColor: Colors.white,
        actions: [_viewModeMenu()],
      ),
      body: body,
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
    Future<void> openSeries(_SeriesEntry entry) async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => BookSeriesDetailScreen(
            seriesId: entry.series.id,
          ),
        ),
      );
      if (mounted) _load();
    }

    if (_layout == _BookLayoutMode.list) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final entry = visible[index];
            final stats = _displayStats(entry);
            return _BookSeriesCompactRow(
              series: entry.series,
              stats: stats,
              onTap: () => openSeries(entry),
            );
          },
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.58,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = visible[index];
            return BookSeriesTile(
              series: entry.series,
              stats: _displayStats(entry),
              accent: BookAccent.primary,
              onDelete: () => _confirmDeleteSeries(entry.series),
              onTap: () => openSeries(entry),
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

/// Ligne compacte série (~76 px) pour mode liste mobile.
class _BookSeriesCompactRow extends StatelessWidget {
  final BookSeries series;
  final BookSeriesStats stats;
  final VoidCallback onTap;

  const _BookSeriesCompactRow({
    required this.series,
    required this.stats,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = series.isStandalone
        ? '${series.subcategory.label} · Œuvre unique'
        : '${series.subcategory.label} · ${stats.totalSlots} tomes';
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 46,
                    height: 66,
                    child: series.coverUrl != null &&
                            series.coverUrl!.trim().isNotEmpty
                        ? CollectionCoverImage(
                            url: series.coverUrl!,
                            bookCover: true,
                            fit: BoxFit.cover,
                          )
                        : CoverImagePlaceholder(bookCover: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        series.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!series.isStandalone && stats.totalSlots > 0) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: stats.ownedProgress,
                            minHeight: 3,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: stats.isComplete
                                ? Colors.green.shade600
                                : const Color(0xFF26A69A),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '📚 ${stats.ownedLabel}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '👁️ ${stats.readLabel}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      stats.ratingLabel ?? '★ —',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
