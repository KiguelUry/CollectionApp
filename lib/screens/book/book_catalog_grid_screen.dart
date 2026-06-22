import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_subcategory.dart';
import '../../services/book_catalog_service.dart';
import '../../services/book_intelligence_service.dart';
import '../../utils/collection_grid_layout.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/catalog/catalog_item_tile.dart';
import '../../widgets/ui/empty_state.dart';

/// Grille visuelle de recherche livres (catalogue OL + Google Books).
class BookCatalogGridScreen extends StatefulWidget {
  final BookSubcategory initialSub;
  final String? initialQuery;
  final void Function(Map<String, String> book, BookSubcategory sub)?
      onBookSelected;

  const BookCatalogGridScreen({
    super.key,
    this.initialSub = BookSubcategory.manga,
    this.initialQuery,
    this.onBookSelected,
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

    if (!mounted) return;
    setState(() {
      _hits = enriched;
      _loading = false;
    });
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
                for (final s in BookSubcategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(s.label, style: const TextStyle(fontSize: 12)),
                      selected: _sub == s,
                      selectedColor: BookAccent.surface,
                      onSelected: (_) {
                        setState(() => _sub = s);
                        if (_searched) _search();
                      },
                      avatar: Icon(s.icon, size: 16, color: s.color),
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
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Text(
            'Open Library + Google Books · tri par popularité',
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: _buildFilters(),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_searched) {
      return EmptyState(
        icon: Icons.auto_stories_outlined,
        title: 'Catalogue visuel',
        message: 'Ex. « Dune », auteur « Herbert », éditeur « Gallimard »…',
        iconColor: _sub.color,
      );
    }
    if (_loading && _hits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hits.isEmpty) {
      return EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Aucun résultat',
        message: 'Affine titre, auteur ou éditeur.',
        iconColor: _sub.color,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      gridDelegate: CollectionGridLayout.gridDelegate(
        context,
        mobileColumns: 3,
        childAspectRatio: 0.52,
        spacing: 10,
      ),
      itemCount: _hits.length,
      itemBuilder: (context, i) {
        final hit = _hits[i];
        final subtitle = [
          if (hit.author != null && hit.author!.isNotEmpty) hit.author,
          if (hit.publisher != null && hit.publisher!.isNotEmpty) hit.publisher,
          if ((hit.raw['year'] ?? '').isNotEmpty) hit.raw['year'],
        ].whereType<String>().join(' · ');
        return CatalogItemTile(
          name: hit.displayTitle,
          imageUrl: hit.imageUrl,
          subtitle: subtitle,
          accent: _accent,
          aspectRatio: 2 / 3,
          placeholderIcon: Icons.menu_book_rounded,
          highQualityImage: true,
          onTap: () => _select(hit),
          onQuickAdd: () => _select(hit),
        );
      },
    );
  }
}
