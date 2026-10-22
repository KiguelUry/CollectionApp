import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_subcategory.dart';
import '../../services/book_catalog_service.dart';
import '../../services/book_intelligence_service.dart';
import '../../services/mangadex_service.dart';
import '../../utils/book_series_normalizer.dart';
import '../../utils/collection_grid_layout.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/catalog/catalog_item_tile.dart';
import '../../widgets/ui/empty_state.dart';

/// Grille visuelle de recherche livres (Google Books + iTunes).
class BookCatalogGridScreen extends StatefulWidget {
  final BookSubcategory initialSub;
  final String? initialQuery;
  final void Function(Map<String, String> book, BookSubcategory sub)?
      onBookSelected;
  final void Function(String seriesName, BookSubcategory sub)? onAddSeries;

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
  bool _loading = false;
  bool _searched = false;
  String? _seriesBannerName;
  int? _seriesBannerVolumes;

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

    final raw = await BookCatalogService.searchBooks(
      apiQuery.length >= 2 ? apiQuery : filters.publisherQuery,
      subcategory: _sub,
      filters: filters,
    );
    final withPhotos = await BookCatalogService.enrichAuthorPhotos(raw);
    final enriched = BookIntelligenceService.enrichAndRank(
      withPhotos,
      subcategory: _sub,
      filters: filters,
    );

    final q = filters.titleQuery.trim();
    String? seriesName = q;
    int? seriesVols = BookSeriesNormalizer.expectedCount(q, _sub);
    if (_sub == BookSubcategory.manga && seriesVols == null) {
      final dex = await MangaDexService.lookupManga(q);
      if (dex != null) {
        seriesName = dex.title;
        seriesVols = dex.volumesPublished;
      }
    }
    // Infère le nom de série depuis le meilleur hit.
    if (enriched.isNotEmpty && enriched.first.parsed.hasSeries) {
      seriesName = enriched.first.parsed.seriesName;
      seriesVols ??= enriched.first.estimatedTotalVolumes ??
          BookSeriesNormalizer.expectedCount(seriesName!, _sub);
    }

    if (!mounted) return;
    setState(() {
      _hits = enriched;
      _seriesBannerName =
          (seriesName != null && seriesName.trim().length >= 2)
              ? seriesName.trim()
              : null;
      _seriesBannerVolumes = seriesVols;
      _loading = false;
    });
  }

  void _addSeries() {
    final name = _seriesBannerName;
    if (name == null) return;
    final cb = widget.onAddSeries;
    if (cb != null) {
      cb(name, _sub);
      return;
    }
    // Fallback : sélectionne un hit synthétique série.
    _select(
      EnrichedBookHit(
        raw: {
          'title': name,
          'series_title': name,
          if (_seriesBannerVolumes != null)
            'estimated_volumes': '$_seriesBannerVolumes',
        },
        parsed: BookSeriesNormalizer.parse(name),
        displayTitle: name,
        score: 999,
        estimatedTotalVolumes: _seriesBannerVolumes,
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
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in BookSubcategory.filterChips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        s.filterLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: _sub == s,
                      selectedColor: BookAccent.surface,
                      onSelected: (_) {
                        setState(() => _sub = s);
                        if (_searched) _search();
                      },
                      showCheckmark: false,
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
            if (_seriesBannerName != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Material(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: _addSeries,
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
                                    'Série : $_seriesBannerName',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    _seriesBannerVolumes != null
                                        ? '$_seriesBannerVolumes tomes parus — Ajouter la série'
                                        : 'Ajouter la série complète',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton(
                              onPressed: _addSeries,
                              child: const Text('Ajouter'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverGrid(
                gridDelegate: CollectionGridLayout.gridDelegate(
                  context,
                  mobileColumns: 3,
                  childAspectRatio: 0.62,
                  spacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final hit = _hits[i];
                    return CatalogItemTile(
                      name: hit.displayTitle,
                      imageUrl: hit.imageUrl,
                      accent: _accent,
                      aspectRatio: 2 / 3,
                      placeholderIcon: Icons.menu_book_rounded,
                      highQualityImage: true,
                      minimalStyle: true,
                      onTap: () => _select(hit),
                      onQuickAdd: () => _select(hit),
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
