import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_set_info.dart';
import '../../services/card_catalog_service.dart';
import '../../services/pokemon_tcg_service.dart';
import '../../services/user_card_collection_service.dart';
import '../../utils/card_quick_add.dart';
import '../../utils/collection_grid_layout.dart';
import '../../utils/tcg_bulk_add.dart';
import '../../utils/tcg_rarity_order.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/cover_preview_sheet.dart';
import '../../widgets/tcg/tcg_catalog_card_tile.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/loading_placeholder.dart';

/// Résultats de recherche catalogue (toutes séries confondues).
class TcgGlobalSearchScreen extends StatefulWidget {
  final CardSubcategory subcategory;
  final String query;

  const TcgGlobalSearchScreen({
    super.key,
    required this.subcategory,
    required this.query,
  });

  @override
  State<TcgGlobalSearchScreen> createState() => _TcgGlobalSearchScreenState();
}

class _TcgGlobalSearchScreenState extends State<TcgGlobalSearchScreen> {
  List<TcgCatalogCard> _cards = [];
  Set<String> _ownedIds = {};
  Set<String> _wishlistIds = {};
  bool _loading = true;
  late String _apiQuery;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _apiQuery = widget.query;
    _searchController = TextEditingController(text: widget.query);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshOwned() async {
    final svc = UserCardCollectionService();
    final owned = await svc.ownedCatalogIds(widget.subcategory);
    final wishlist = await svc.wishlistCatalogIds(widget.subcategory);
    if (mounted) {
      setState(() {
        _ownedIds = owned;
        _wishlistIds = wishlist;
      });
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final hits = await CardCatalogService.search(
        _apiQuery,
        subcategory: widget.subcategory,
      );
      final cards = CardCatalogService.catalogCardsFromSearchHits(
        hits,
        widget.subcategory,
      );
      final svc = UserCardCollectionService();
      final owned = await svc.ownedCatalogIds(widget.subcategory);
      final wishlist = await svc.wishlistCatalogIds(widget.subcategory);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _ownedIds = owned;
        _wishlistIds = wishlist;
        _loading = false;
      });
      if (widget.subcategory == CardSubcategory.pokemon) {
        _maybeEnrichPokemonRarities();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _maybeEnrichPokemonRarities() async {
    if (!_cards.any((c) => c.rarity == null || c.rarity!.isEmpty)) return;
    final copy = List<TcgCatalogCard>.from(_cards);
    await PokemonTcgService.enrichRarities(copy);
    if (!mounted) return;
    setState(() => _cards = copy);
  }

  void _showAddedSnack(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text('« $name » a été ajouté à la collection'),
      ),
    );
  }

  Future<void> _quickAddCard(TcgCatalogCard card) async {
    final ok = await silentAddTcgCard(
      context,
      subcategory: widget.subcategory,
      card: card,
    );
    if (!mounted || !ok) return;
    setState(() {
      _ownedIds.add(card.id);
      _wishlistIds.remove(card.id);
    });
    _showAddedSnack(card.name);
  }

  Future<void> _toggleWishlist(TcgCatalogCard card) async {
    final inWishlist = _wishlistIds.contains(card.id);
    final ok = await toggleTcgWishlist(
      context,
      subcategory: widget.subcategory,
      card: card,
      currentlyInWishlist: inWishlist,
    );
    if (!mounted || !ok) return;
    setState(() {
      if (inWishlist) {
        _wishlistIds.remove(card.id);
      } else {
        _wishlistIds.add(card.id);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(
          inWishlist
              ? '« ${card.name} » retiré de la wishlist'
              : '« ${card.name} » ajouté à la wishlist',
        ),
      ),
    );
  }

  List<TcgCatalogCard> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    var list = _cards;
    if (q.isNotEmpty) {
      list = list.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    final sorted = List<TcgCatalogCard>.from(list);
    sortTcgCardsByRarity(
      sorted,
      widget.subcategory,
      rarityOf: (c) => c.rarity,
      tieBreaker: (c) => c.name,
      numberOf: (c) => c.number,
    );
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final title = '« $_apiQuery » — ${widget.subcategory.label}';

    return Scaffold(
      appBar: AppAppBar(title: title),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Affiner la recherche…',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              controller: _searchController,
              onSubmitted: (v) {
                final trimmed = v.trim();
                if (trimmed.length >= 2 && trimmed != _apiQuery) {
                  setState(() => _apiQuery = trimmed);
                  _load();
                }
              },
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: _loading
                ? LoadingPlaceholder(
                    grid: false,
                    count: 8,
                    message: 'Recherche en cours…',
                  )
                : filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.style_outlined,
                        title: 'Aucune carte',
                        message: 'Essaie un autre nom ou un autre univers.',
                        iconColor: widget.subcategory.color,
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: CollectionGridLayout.gridDelegate(
                          context,
                          mobileColumns: 3,
                          childAspectRatio: 0.5,
                          spacing: 4,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final card = filtered[i];
                          final owned = _ownedIds.contains(card.id);
                          final inWishlist = _wishlistIds.contains(card.id);
                          return TcgCatalogCardTile(
                            name: card.name,
                            imageUrl: card.imageUrl,
                            accent: widget.subcategory.color,
                            owned: owned,
                            inWishlist: inWishlist,
                            onTap: () => quickAddTcgCatalogCard(
                              context,
                              subcategory: widget.subcategory,
                              card: card,
                            ).then((_) => _refreshOwned()),
                            onLongPress: () => showCoverPreview(
                              context,
                              imageUrl: card.imageUrl,
                              title: card.name,
                            ),
                            onQuickAdd: () => _quickAddCard(card),
                            onQuickWishlist:
                                owned ? null : () => _toggleWishlist(card),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
