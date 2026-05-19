import 'package:flutter/material.dart';
import '../models/book_subcategory.dart';
import '../services/open_library_service.dart';
import '../utils/debounced_runner.dart';
import '../utils/dialog_layout.dart';
import 'collection_cover_image.dart';

class BookSearchDialog extends StatefulWidget {
  final void Function(Map<String, String> book, BookSubcategory subcategory)
      onBookSelected;

  const BookSearchDialog({super.key, required this.onBookSelected});

  @override
  State<BookSearchDialog> createState() => _BookSearchDialogState();
}

class _BookSearchDialogState extends State<BookSearchDialog> {
  final _controller = TextEditingController();
  final _debounce = DebouncedRunner();
  BookSubcategory _subcategory = BookSubcategory.manga;
  List<Map<String, String>> _results = [];
  bool _isLoading = false;
  String? _lastQuery;
  int _searchGeneration = 0;

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
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
        _lastQuery = null;
      });
      return;
    }
    _debounce.run(
      delay: const Duration(milliseconds: 400),
      action: () => _search(query),
    );
  }

  void _setSubcategory(BookSubcategory sub) {
    if (_subcategory == sub) return;
    setState(() => _subcategory = sub);
    final q = _controller.text.trim();
    if (q.length >= 2) _search(q);
  }

  Future<void> _search(String query) async {
    if (query.length < 2) return;

    final generation = ++_searchGeneration;
    setState(() {
      _isLoading = true;
      _lastQuery = query;
    });

    final res = await OpenLibraryService.searchBooks(
      query,
      subcategory: _subcategory,
    );
    if (!mounted || generation != _searchGeneration) return;

    setState(() {
      _results = res;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chercher un livre'),
      content: SizedBox(
        width: double.maxFinite,
        height: adaptiveDialogContentHeight(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: BookSubcategory.values.map((s) {
                return FilterChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 12)),
                  selected: _subcategory == s,
                  onSelected: (_) => _setSubcategory(s),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Tape pour chercher (ex: One Piece, Astérix…)',
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
              ),
            ),
            if (_lastQuery != null && _lastQuery!.isNotEmpty && !_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  _results.isEmpty
                      ? 'Aucun ${_subcategory.label.toLowerCase()} pour « $_lastQuery »'
                      : '${_results.length} ${_subcategory.label.toLowerCase()}(s)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
            Expanded(
              child: _results.isEmpty && !_isLoading
                  ? Center(
                      child: Text(
                        _controller.text.trim().length < 2
                            ? 'Choisis un type puis tape au moins 2 caractères'
                            : 'Aucun résultat dans cette catégorie',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final book = _results[index];
                        final imageUrl = book['image_url'];
                        final ratingAvg = book['rating_avg'];
                        final ratingCount = book['rating_count'];
                        final parts = <String>[
                          book['author']!,
                          if (book['year']!.isNotEmpty) book['year']!,
                          if (ratingAvg != null &&
                              (int.tryParse(ratingCount ?? '0') ?? 0) > 0)
                            '★ $ratingAvg ($ratingCount avis)',
                        ];
                        return ListTile(
                          leading: imageUrl != null && imageUrl.isNotEmpty
                              ? CollectionCoverImage(
                                  url: imageUrl,
                                  width: 40,
                                  height: 58,
                                  bookCover: true,
                                )
                              : const Icon(Icons.menu_book),
                          title: Text(book['title']!),
                          subtitle: Text(parts.join(' · ')),
                          onTap: () =>
                              widget.onBookSelected(book, _subcategory),
                        );
                      },
                    ),
            ),
            const Divider(),
            const Text(
              'Powered by Open Library',
              style: TextStyle(fontSize: 9, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
