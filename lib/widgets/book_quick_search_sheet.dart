import 'package:flutter/material.dart';

import '../models/book_subcategory.dart';
import '../services/book_catalog_service.dart';
import '../utils/debounced_runner.dart';
import 'collection_cover_image.dart';
import 'ui/empty_state.dart';

Future<void> showBookQuickSearchSheet(
  BuildContext context, {
  required void Function(Map<String, String> book, BookSubcategory sub) onBookSelected,
  BookSubcategory initialSub = BookSubcategory.manga,
  VoidCallback? onManualEntry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _BookQuickSearchSheet(
      initialSub: initialSub,
      onBookSelected: onBookSelected,
      onManualEntry: onManualEntry,
    ),
  );
}

class _BookQuickSearchSheet extends StatefulWidget {
  final BookSubcategory initialSub;
  final void Function(Map<String, String> book, BookSubcategory sub) onBookSelected;
  final VoidCallback? onManualEntry;

  const _BookQuickSearchSheet({
    required this.initialSub,
    required this.onBookSelected,
    this.onManualEntry,
  });

  @override
  State<_BookQuickSearchSheet> createState() => _BookQuickSearchSheetState();
}

class _BookQuickSearchSheetState extends State<_BookQuickSearchSheet> {
  late BookSubcategory _sub = widget.initialSub;
  final _controller = TextEditingController();
  final _debounce = DebouncedRunner();
  List<Map<String, String>> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _debounce.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final q = _controller.text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    _debounce.run(
      delay: const Duration(milliseconds: 450),
      action: () => _search(q),
    );
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _searched = true;
    });

    final res = await BookCatalogService.searchBooks(
      query,
      subcategory: _sub,
    );

    if (!mounted) return;
    setState(() {
      _results = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Trouver un livre',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final s in BookSubcategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(s.label, style: const TextStyle(fontSize: 12)),
                      selected: _sub == s,
                      onSelected: (_) {
                        setState(() => _sub = s);
                        final q = _controller.text.trim();
                        if (q.length >= 2) _search(q);
                      },
                      avatar: Icon(s.icon, size: 16, color: s.color),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _sub.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Text(
              'Open Library + Google Books',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: _buildBody()),
          if (widget.onManualEntry != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onManualEntry!();
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Saisie manuelle'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_searched) {
      return EmptyState(
        icon: Icons.auto_stories_outlined,
        title: 'Recherche instantanée',
        message: 'Ex. One Piece, Astérix, Harry Potter…',
        iconColor: _sub.color,
      );
    }
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Aucun résultat',
        message: 'Change de type ou de mot-clé.',
        iconColor: _sub.color,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final book = _results[i];
        final imageUrl = book['image_url'];
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.pop(context);
              widget.onBookSelected(book, _sub);
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? CollectionCoverImage(
                            url: imageUrl,
                            width: 44,
                            height: 64,
                            bookCover: true,
                          )
                        : Container(
                            width: 44,
                            height: 64,
                            color: _sub.color.withValues(alpha: 0.12),
                            child: Icon(_sub.icon, color: _sub.color),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book['title'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if ((book['author'] ?? '').isNotEmpty) book['author'],
                            if ((book['year'] ?? '').isNotEmpty) book['year'],
                          ].whereType<String>().join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.add_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
