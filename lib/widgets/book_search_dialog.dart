import 'package:flutter/material.dart';
import '../models/book_subcategory.dart';
import '../services/open_library_service.dart';

class BookSearchDialog extends StatefulWidget {
  final void Function(Map<String, String> book, BookSubcategory subcategory)
      onBookSelected;

  const BookSearchDialog({super.key, required this.onBookSelected});

  @override
  State<BookSearchDialog> createState() => _BookSearchDialogState();
}

class _BookSearchDialogState extends State<BookSearchDialog> {
  final _controller = TextEditingController();
  BookSubcategory _subcategory = BookSubcategory.manga;
  List<Map<String, String>> _results = [];
  bool _isLoading = false;

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
              decoration: InputDecoration(
                hintText: 'Titre, auteur…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_controller.text),
                ),
              ),
              onSubmitted: _search,
            ),
            if (_isLoading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final book = _results[index];
                  final imageUrl = book['image_url'];
                  return ListTile(
                    leading: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(imageUrl, width: 40, fit: BoxFit.cover)
                        : const Icon(Icons.menu_book),
                    title: Text(book['title']!),
                    subtitle: Text(
                      '${book['author']}${book['year']!.isNotEmpty ? ' · ${book['year']}' : ''}',
                    ),
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

  Future<void> _search(String query) async {
    if (query.length < 2) return;
    setState(() => _isLoading = true);
    final res = await OpenLibraryService.searchBooks(query);
    setState(() {
      _results = res;
      _isLoading = false;
    });
  }
}
