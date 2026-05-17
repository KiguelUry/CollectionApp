import 'package:flutter/material.dart';
import '../models/book_subcategory.dart';
import '../services/open_library_service.dart';
import '../utils/debounced_runner.dart';

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
      });
      return;
    }
    _debounce.run(
      delay: const Duration(milliseconds: 400),
      action: () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    if (query.length < 2) return;

    final generation = ++_searchGeneration;
    setState(() => _isLoading = true);

    final res = await OpenLibraryService.searchBooks(query);
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
        height: 480,
        child: Column(
          children: [
            DropdownButtonFormField<BookSubcategory>(
              initialValue: _subcategory,
              decoration: const InputDecoration(labelText: 'Type'),
              items: BookSubcategory.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.label),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _subcategory = val);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Tape pour chercher…',
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
            Expanded(
              child: ListView.builder(
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
                        ? Image.network(imageUrl, width: 40, fit: BoxFit.cover)
                        : const Icon(Icons.menu_book),
                    title: Text(book['title']!),
                    subtitle: Text(parts.join(' · ')),
                    onTap: () => widget.onBookSelected(book, _subcategory),
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
