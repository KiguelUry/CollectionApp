import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../services/wishlist_suggestion_service.dart';
import 'bgg_network_image.dart';

/// Bandeau « Tu pourrais ajouter… » (jeux de société, wishlist).
class WishlistSuggestionsBanner extends StatefulWidget {
  final CollectionCategory category;

  const WishlistSuggestionsBanner({super.key, required this.category});

  @override
  State<WishlistSuggestionsBanner> createState() =>
      _WishlistSuggestionsBannerState();
}

class _WishlistSuggestionsBannerState extends State<WishlistSuggestionsBanner> {
  final _service = WishlistSuggestionService();
  List<WishlistSuggestion> _suggestions = [];
  bool _loading = true;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.category != CollectionCategory.boardgame) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final list = await _service.fetchBoardgameSuggestions();
      if (mounted) setState(() => _suggestions = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.category != CollectionCategory.boardgame) {
      return const SizedBox.shrink();
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: LinearProgressIndicator(),
      );
    }
    if (_suggestions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(
              alpha: 0.35,
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text(
                'Tu pourrais ajouter…',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'D\'après les jeux bien notés de tes amis (genres BGG)',
                style: TextStyle(fontSize: 12),
              ),
              trailing: IconButton(
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ),
            if (_expanded)
              ..._suggestions.map(
                (s) => ListTile(
                  dense: true,
                  leading: s.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: BggNetworkImage(url: s.imageUrl!),
                          ),
                        )
                      : const Icon(Icons.extension),
                  title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    s.reason,
                    style: const TextStyle(fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
