import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_subcategory.dart';
import '../../services/book_catalog_service.dart';
import '../../services/book_intelligence_service.dart';
import '../../utils/book_series_normalizer.dart';
import '../../utils/collection_grid_layout.dart' show CollectionGridLayout;
import '../../widgets/app_app_bar.dart';
import '../../widgets/catalog/catalog_item_tile.dart';
import '../../widgets/ui/empty_state.dart';

/// Grille visuelle de recherche livres (Google Books + iTunes).
class BookCatalogGridScreen extends StatefulWidget {
  final BookSubcategory initialSub;
  final String? initialQuery;
  final void Function(Map<String, String> book, BookSubcategory sub)?
      onBookSelected;
  final void Function(
    String seriesName,
    BookSubcategory sub, {
    int? volumeCount,
    Map<int, String>? coversByVolume,
  })? onAddSeries;

  const BookCatalogGridScreen({
    super.key,
    this.initialSub = BookSubcategory.manga,
    this.initialQuery,
    this.onBookSelected,
    this.onAddSeries,
  });

  @override
  State<BookCatalogGridScreen> createState() => _BookCatalogGridScreenState();
}

class _BookCatalogGridScreenState extends State<BookCatalogGridScreen> {
  static const _accent = BookAccent.primary;

  late BookSubcategory _sub = widget.initialSub;
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _publisherController = TextEditingController();

  List<EnrichedBookHit> _hits = [];
  List<SeriesBannerCandidate> _banners = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.length >= 2) {
      _titleController.text = widget.initialQuery!;
      _search();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    super.dispose();
  }

  BookSearchFilters get _filters => BookSearchFilters(
        titleQuery: _titleController.text,
        authorQuery: _authorController.text,
        publisherQuery: _publisherController.text,
      );

  Future<void> _search() async {
    final filters = _filters;
    final apiQuery = filters.combinedQuery;
    if (apiQuery.length < 2 && filters.publisherQuery.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saisis au moins 2 caractères (titre ou auteur).'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _searched = true;
    });

    final q = filters.titleQuery.trim().isNotEmpty
        ? filters.titleQuery.trim()
        : apiQuery;
    // Recherche « Titre Tome » pour maximiser les couvertures par numéro.
    final tomeQuery = q.toLowerCase().contains('tome') ? q : '$q Tome';
    final raw = await BookCatalogService.searchBooks(
      tomeQuery.length >= 2 ? tomeQuery : filters.publisherQuery,
      subcategory: _sub,
      filters: filters,
    );
    final withPhotos = await BookCatalogService.enrichAuthorPhotos(raw);
    final enriched = BookIntelligenceService.enrichAndRank(
      withPhotos,
      subcategory: _sub,
      filters: filters,
    );

    var banners = BookIntelligenceService.extractSeriesBanners(
      enriched,
      query: q,
      subcategory: _sub,
    );
    // Filet de sécurité : max(dict, max tome dans résultats).
    banners = [
      for (final b in banners)
        SeriesBannerCandidate(
          name: b.name,
          volumeCount: () {
            final dict =
                BookSeriesNormalizer.expectedCount(b.name, _sub) ?? 0;
            return dict > b.volumeCount ? dict : b.volumeCount;
          }(),
          coversByVolume: b.coversByVolume,
        ),
    ];

    if (!mounted) return;
    setState(() {
      _hits = enriched;
      _banners = banners;
      _loading = false;
    });
  }

  void _addSeries(SeriesBannerCandidate banner) {
    final preferred =
        BookSeriesNormalizer.preferredSubcategory(banner.name) ?? _sub;
    final cb = widget.onAddSeries;
    if (cb != null) {
      cb(
        banner.name,
        preferred,
        volumeCount: banner.volumeCount,
        coversByVolume: banner.coversByVolume,
      );
      return;
    }
    _select(
      EnrichedBookHit(
        raw: {
          'title': banner.name,
          'series_title': banner.name,
          'estimated_volumes': '${banner.volumeCount}',
          if (banner.coversByVolume[1] != null)
            'image_url': banner.coversByVolume[1]!,
          'volume_covers_json': banner.coversByVolume.entries
              .map((e) => '${e.key}:${e.value}')
              .join('|'),
        },
        parsed: BookSeriesNormalizer.parse(banner.name),
        displayTitle: banner.name,
        score: 999,
        estimatedTotalVolumes: banner.volumeCount,
      ),
    );
  }

  void _select(EnrichedBookHit hit) {
    final callback = widget.onBookSelected;
    if (callback != null) {
      callback(hit.raw, _sub);
      return;
    }
    Navigator.pop(context, (hit.raw, _sub));
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in BookSubcategory.filterChips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: Text(s.filterEmoji),
                      label: Text(s.label),
                      selected: _sub == s,
                      selectedColor: BookAccent.surface,
                      showCheckmark: false,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelPadding: const EdgeInsets.only(left: 2, right: 8),
                      onSelected: (_) {
                        setState(() => _sub = s);
                        if (_searched) _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    hintText: 'Titre',
                    isDense: true,
                    prefixIcon: Icon(Icons.menu_book_outlined, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _authorController,
                  decoration: const InputDecoration(
                    hintText: 'Auteur',
                    isDense: true,
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _publisherController,
                  decoration: const InputDecoration(
                    hintText: 'Éditeur',
                    isDense: true,
                    prefixIcon: Icon(Icons.business_outlined, size: 20),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Text(
            'Google Books + iTunes · couvertures HD',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBanner(SeriesBannerCandidate banner) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: _accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _addSeries(banner),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Text('📚', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Série : ${banner.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${banner.volumeCount} tomes parus — Ajouter la série',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => _addSeries(banner),
                  child: const Text('Ajouter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppAppBar(
        title: 'Recherche livres',
        backgroundColor: _accent,
        foregroundColor: Colors.white,
      ),
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: _buildFilters()),
          if (!_searched)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.auto_stories_outlined,
                title: 'Catalogue visuel',
                message: 'Ex. « Kagurabachi », « Dune », auteur « Herbert »…',
                iconColor: _sub.color,
              ),
            )
          else if (_loading && _hits.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hits.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'Aucun résultat',
                message: 'Affine titre, auteur ou éditeur.',
                iconColor: _sub.color,
              ),
            )
          else ...[
            if (_banners.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    for (final b in _banners) _buildBanner(b),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverGrid(
                gridDelegate: CollectionGridLayout.gridDelegate(
                  context,
                  mobileColumns: 3,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final hit = _hits[index];
                    return CatalogItemTile(
                      name: hit.displayTitle,
                      subtitle: [
                        if (hit.author != null && hit.author!.isNotEmpty)
                          hit.author!,
                        if (hit.parsed.volumeNumber != null)
                          'Tome ${hit.parsed.volumeNumber!.round()}',
                      ].join(' · '),
                      imageUrl: hit.imageUrl,
                      accent: _sub.color,
                      aspectRatio: 0.65,
                      highQualityImage: true,
                      placeholderIcon: Icons.menu_book_outlined,
                      onTap: () => _select(hit),
                    );
                  },
                  childCount: _hits.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
