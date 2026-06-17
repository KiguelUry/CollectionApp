import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_set_info.dart';
import '../../models/pokemon_card_lang.dart';
import '../../services/card_catalog_service.dart';
import '../../services/pokemon_tcg_service.dart';
import '../../services/user_card_collection_service.dart';
import '../../utils/card_quick_add.dart';
import '../../utils/collection_grid_layout.dart';
import '../../utils/tcg_bulk_add.dart';
import '../../utils/tcg_card_display.dart';
import '../../utils/tcg_rarity_order.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/cover_preview_sheet.dart';
import '../../widgets/tcg/tcg_catalog_card_tile.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/loading_placeholder.dart';

enum _GlobalSearchSort { name, rarity }

/// Résultats de recherche catalogue (toutes séries confondues).
class TcgGlobalSearchScreen extends StatefulWidget {
  final CardSubcategory subcategory;
  final String query;
  final String? pokemonLang;

  const TcgGlobalSearchScreen({
    super.key,
    required this.subcategory,
    required this.query,
    this.pokemonLang,
  });

  @override
  State<TcgGlobalSearchScreen> createState() => _TcgGlobalSearchScreenState();
}

class _TcgGlobalSearchScreenState extends State<TcgGlobalSearchScreen> {
  List<TcgCatalogCard> _cards = [];
  Set<String> _ownedIds = {};
  Set<String> _wishlistIds = {};
  bool _loading = true;
  bool _enrichingRarities = false;
  late String _apiQuery;
  late String _pokemonLang;
  late final TextEditingController _searchController;
  _GlobalSearchSort _sort = _GlobalSearchSort.name;
  final Set<String> _rarityFilters = {};
  final Set<String> _typeFilters = {};

  static const _pokemonTypes = [
    'Colorless',
    'Darkness',
    'Dragon',
    'Fairy',
    'Fighting',
    'Fire',
    'Grass',
    'Lightning',
    'Metal',
    'Psychic',
    'Water',
  ];

  @override
  void initState() {
    super.initState();
    _apiQuery = widget.query;
    _pokemonLang = widget.pokemonLang ?? PokemonCardLang.fr;
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
        pokemonLang: _pokemonLang,
      );
      final cards = CardCatalogService.catalogCardsFromSearchHits(
        hits,
        widget.subcategory,
      );
      if (widget.subcategory == CardSubcategory.pokemon) {
        PokemonTcgService.fillMissingCardImages(cards);
      }
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
        _maybeEnrichPokemonDetails();
        _maybeEnrichSearchMeta();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _maybeEnrichSearchMeta() async {
    if (widget.subcategory != CardSubcategory.pokemon) return;
    final copy = List<TcgCatalogCard>.from(_cards);
    await PokemonTcgService.enrichSearchMetadata(copy, lang: _pokemonLang);
    if (!mounted) return;
    setState(() => _cards = copy);
  }

  Future<void> _maybeEnrichPokemonDetails() async {
    setState(() => _enrichingRarities = true);
    final copy = List<TcgCatalogCard>.from(_cards);
    await PokemonTcgService.enrichCardDetails(copy);
    if (!mounted) return;
    setState(() {
      _cards = copy;
      _enrichingRarities = false;
    });
  }

  Set<String> get _rarityOptions {
    final out = <String>{};
    for (final c in _cards) {
      final r = c.rarity?.trim();
      if (r != null && r.isNotEmpty) out.add(r);
    }
    return out;
  }

  Set<String> get _typeOptions {
    if (widget.subcategory != CardSubcategory.pokemon) return {};
    final out = <String>{};
    for (final c in _cards) {
      final types = c.raw['types'];
      if (types != null && types.isNotEmpty) {
        for (final t in types.split(',')) {
          final s = t.trim();
          if (s.isNotEmpty) out.add(s);
        }
      }
    }
    if (out.isEmpty) return _pokemonTypes.toSet();
    return out;
  }

  List<String> get _sortedRarityOptions =>
      sortRarityLabels(_rarityOptions.toList(), widget.subcategory);

  String _catalogKey(TcgCatalogCard card) =>
      UserCardCollectionService.catalogKeyForTcgCard(card, widget.subcategory);

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
      _ownedIds.add(_catalogKey(card));
      _wishlistIds.remove(_catalogKey(card));
    });
    _showAddedSnack(card.name);
  }

  Future<void> _toggleWishlist(TcgCatalogCard card) async {
    final key = _catalogKey(card);
    final inWishlist = _wishlistIds.contains(key);
    final ok = await toggleTcgWishlist(
      context,
      subcategory: widget.subcategory,
      card: card,
      currentlyInWishlist: inWishlist,
    );
    if (!mounted || !ok) return;
    setState(() {
      if (inWishlist) {
        _wishlistIds.remove(key);
      } else {
        _wishlistIds.add(key);
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
    if (_rarityFilters.isNotEmpty) {
      list = list
          .where(
            (c) =>
                c.rarity != null &&
                _rarityFilters.any(
                  (r) => r.toLowerCase() == c.rarity!.toLowerCase(),
                ),
          )
          .toList();
    }
    if (_typeFilters.isNotEmpty) {
      list = list.where((c) {
        final types = c.raw['types']?.split(',') ?? [];
        return types.any(
          (t) => _typeFilters.any(
            (sel) => sel.toLowerCase() == t.trim().toLowerCase(),
          ),
        );
      }).toList();
    }
    final sorted = List<TcgCatalogCard>.from(list);
    if (_sort == _GlobalSearchSort.name) {
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    } else {
      sortTcgCardsByRarity(
        sorted,
        widget.subcategory,
        rarityOf: (c) => c.rarity,
        tieBreaker: (c) => c.name,
        numberOf: (c) => c.number,
      );
    }
    return sorted;
  }

  Future<void> _openFilterDialog({
    required String title,
    required List<String> options,
    required Set<String> selected,
    required void Function(Set<String>) onApply,
  }) async {
    final tmp = Set<String>.from(selected);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in options)
                    FilterChip(
                      label: Text(o, style: const TextStyle(fontSize: 12)),
                      selected: tmp.contains(o),
                      onSelected: (v) => setStateDialog(() {
                        if (v) {
                          tmp.add(o);
                        } else {
                          tmp.remove(o);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, <String>{}),
              child: const Text('Tout'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, tmp),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    onApply(result);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
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
                if (widget.subcategory == CardSubcategory.pokemon) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final lang in PokemonCardLang.all)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(PokemonCardLang.label(lang),
                                  style: const TextStyle(fontSize: 11)),
                              selected: _pokemonLang == lang,
                              onSelected: (_) {
                                if (_pokemonLang == lang) return;
                                setState(() => _pokemonLang = lang);
                                _load();
                              },
                              showCheckmark: false,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${filtered.length} carte${filtered.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const Spacer(),
                    if (_enrichingRarities)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.subcategory.color,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: _rarityFilters.isEmpty
                          ? 'Filtrer par rareté'
                          : 'Rareté (${_rarityFilters.length})',
                      icon: Icon(
                        Icons.star_outline,
                        size: 20,
                        color: _rarityFilters.isNotEmpty
                            ? widget.subcategory.color
                            : null,
                      ),
                      onPressed: _sortedRarityOptions.isEmpty
                          ? null
                          : () => _openFilterDialog(
                                title: 'Rareté',
                                options: _sortedRarityOptions,
                                selected: _rarityFilters,
                                onApply: (s) => setState(() {
                                  _rarityFilters
                                    ..clear()
                                    ..addAll(s);
                                }),
                              ),
                    ),
                    if (widget.subcategory == CardSubcategory.pokemon)
                      IconButton(
                        tooltip: _typeFilters.isEmpty
                            ? 'Type Pokémon'
                            : 'Type (${_typeFilters.length})',
                        icon: Icon(
                          Icons.bolt_outlined,
                          size: 20,
                          color: _typeFilters.isNotEmpty
                              ? widget.subcategory.color
                              : null,
                        ),
                        onPressed: () => _openFilterDialog(
                          title: 'Type Pokémon',
                          options: _typeOptions.toList()..sort(),
                          selected: _typeFilters,
                          onApply: (s) => setState(() {
                            _typeFilters
                              ..clear()
                              ..addAll(s);
                          }),
                        ),
                      ),
                    FilterChip(
                      label: const Text('Nom', style: TextStyle(fontSize: 11)),
                      selected: _sort == _GlobalSearchSort.name,
                      onSelected: (_) =>
                          setState(() => _sort = _GlobalSearchSort.name),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    FilterChip(
                      label: const Text('Rareté', style: TextStyle(fontSize: 11)),
                      selected: _sort == _GlobalSearchSort.rarity,
                      onSelected: (_) =>
                          setState(() => _sort = _GlobalSearchSort.rarity),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (!_loading && _cards.length >= 500)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '500+ résultats max — affine ta recherche pour en voir plus.',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
              ],
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
                          final owned = _ownedIds.contains(_catalogKey(card));
                          final inWishlist =
                              _wishlistIds.contains(_catalogKey(card));
                          return TcgCatalogCardTile(
                            name: card.name,
                            imageUrl: card.imageUrl,
                            subtitle: tcgCatalogSubtitle(card),
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
