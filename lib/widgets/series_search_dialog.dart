import 'package:flutter/material.dart';

import '../models/book_subcategory.dart';
import '../models/series_search_hit.dart';
import '../services/open_library_service.dart';
import '../utils/debounced_runner.dart';
import '../utils/dialog_layout.dart';
import 'collection_cover_image.dart';

/// Recherche et sélection d'une série (pas d'un tome précis).
Future<SeriesSearchHit?> showSeriesSearchDialog(
  BuildContext context, {
  required BookSubcategory subcategory,
}) {
  return showDialog<SeriesSearchHit>(
    context: context,
    builder: (ctx) => _SeriesSearchDialog(subcategory: subcategory),
  );
}

class _SeriesSearchDialog extends StatefulWidget {
  final BookSubcategory subcategory;

  const _SeriesSearchDialog({required this.subcategory});

  @override
  State<_SeriesSearchDialog> createState() => _SeriesSearchDialogState();
}

class _SeriesSearchDialogState extends State<_SeriesSearchDialog> {
  final _controller = TextEditingController();
  final _debounce = DebouncedRunner();
  List<SeriesSearchHit> _results = [];
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _debounce.dispose();
    super.dispose();
  }

  void _onChanged() {
    final q = _controller.text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    _debounce.run(
      delay: const Duration(milliseconds: 400),
      action: () => _search(q),
    );
  }

  Future<void> _search(String query) async {
    final gen = ++_generation;
    setState(() => _loading = true);
    final res = await OpenLibraryService.searchSeriesCandidates(
      query,
      subcategory: widget.subcategory,
    );
    if (!mounted || gen != _generation) return;
    setState(() {
      _results = res;
      _loading = false;
    });
  }

  void _select(SeriesSearchHit hit) => Navigator.pop(context, hit);

  void _createManual() {
    final name = _controller.text.trim();
    if (name.length < 2) return;
    Navigator.pop(
      context,
      SeriesSearchHit(name: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Série · ${widget.subcategory.label}'),
      content: SizedBox(
        width: double.maxFinite,
        height: adaptiveDialogContentHeight(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nom de la série',
                hintText: 'Thorgal, Naruto, Batman…',
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty && !_loading
                  ? Center(
                      child: Text(
                        _controller.text.trim().length < 2
                            ? 'Tape au moins 2 lettres'
                            : 'Aucune série trouvée — tu peux créer manuellement',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final hit = _results[i];
                        return ListTile(
                          leading: _Cover(url: hit.coverUrl),
                          title: Text(hit.name),
                          subtitle: Text(
                            [
                              if (hit.estimatedVolumes != null)
                                '~${hit.estimatedVolumes} tomes',
                              if (hit.author != null) hit.author!,
                            ].join(' · '),
                          ),
                          onTap: () => _select(hit),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        if (_controller.text.trim().length >= 2)
          FilledButton(
            onPressed: _createManual,
            child: Text('Créer « ${_controller.text.trim()} »'),
          ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  final String? url;

  const _Cover({this.url});

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    if (url != null && url!.isNotEmpty) {
      return CollectionCoverImage(
        url: url!,
        width: size,
        height: size * 1.4,
        bookCover: true,
      );
    }
    return _placeholder(size);
  }

  Widget _placeholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.auto_stories, size: 28),
    );
  }
}
