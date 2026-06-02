import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_set_info.dart';
import '../../services/lorcast_service.dart';
import '../../services/onepiece_tcg_service.dart';
import '../../services/pokemon_tcg_service.dart';
import '../../services/scryfall_service.dart';
import '../../services/ygoprodeck_service.dart';
import '../../services/user_card_collection_service.dart';
import '../../utils/card_quick_add.dart';
import '../../utils/tcg_bulk_add.dart';
import '../../utils/tcg_rarity_order.dart';
import 'tcg_rarity_gallery_screen.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/tcg/tcg_catalog_card_tile.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/loading_placeholder.dart';

/// Toutes les cartes d'une extension + filtres + badge possédé.
class TcgSetCardsScreen extends StatefulWidget {
  final CardSubcategory subcategory;
  final TcgSetInfo set;

  const TcgSetCardsScreen({
    super.key,
    required this.subcategory,
    required this.set,
  });

  @override
  State<TcgSetCardsScreen> createState() => _TcgSetCardsScreenState();
}

class _TcgSetCardsScreenState extends State<TcgSetCardsScreen> {
  List<TcgCatalogCard> _cards = [];
  Set<String> _ownedIds = {};
  bool _loading = true;
  bool _ownedOnly = false;
  String _query = '';
  final Set<String> _rarityFilters = {};
  final Set<String> _typeFilters = {};
  bool _bulkMode = false;
  final Set<String> _selectedIds = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshOwned() async {
    final owned =
        await UserCardCollectionService().ownedCatalogIds(widget.subcategory);
    if (mounted) setState(() => _ownedIds = owned);
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
    setState(() => _ownedIds.add(card.id));
    _showAddedSnack(card.name);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cards = await _fetchCards();
      final owned =
          await UserCardCollectionService().ownedCatalogIds(widget.subcategory);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _ownedIds = owned;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<TcgCatalogCard>> _fetchCards() async {
    return switch (widget.subcategory) {
      CardSubcategory.pokemon =>
        PokemonTcgService.fetchCardsInSet(widget.set.id),
      CardSubcategory.magic =>
        ScryfallService.fetchCardsInSet(widget.set.code ?? widget.set.id),
      CardSubcategory.yugioh =>
        YgoprodeckService.fetchCardsInSet(widget.set.name),
      CardSubcategory.onepiece =>
        OnepieceTcgService.fetchCardsInSet(widget.set.id),
      CardSubcategory.lorcana =>
        LorcastService.fetchCardsInSet(widget.set.id),
      _ => [],
    };
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
    return out;
  }

  List<TcgCatalogCard> get _filtered {
    var list = _cards;
    if (_ownedOnly) {
      list = list.where((c) => _ownedIds.contains(c.id)).toList();
    }
    final q = _query.trim().toLowerCase();
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
    sortTcgCardsByRarity(
      sorted,
      widget.subcategory,
      rarityOf: (c) => c.rarity,
      tieBreaker: (c) => c.name,
      numberOf: (c) => c.number,
    );
    return sorted;
  }

  List<String> get _sortedRarityOptions =>
      sortRarityLabels(_rarityOptions.toList(), widget.subcategory);

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final ownedInSet =
        _cards.where((c) => _ownedIds.contains(c.id)).length;

    return Scaffold(
      appBar: AppAppBar(
        title: widget.set.displayName,
        actions: [
          IconButton(
            tooltip: 'Vue par rareté',
            icon: const Icon(Icons.star_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => TcgRarityGalleryScreen(
                  subcategory: widget.subcategory,
                  title: widget.set.displayName,
                  sets: const [],
                  singleSet: widget.set,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _bulkMode ? 'Annuler sélection' : 'Ajout rapide',
            icon: Icon(_bulkMode ? Icons.close : Icons.playlist_add_check),
            onPressed: () => setState(() {
              _bulkMode = !_bulkMode;
              _selectedIds.clear();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Nom de carte…',
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 6),
                if (_sortedRarityOptions.isNotEmpty)
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final r in _sortedRarityOptions)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(r, style: const TextStyle(fontSize: 11)),
                              selected: _rarityFilters.contains(r),
                              onSelected: (on) => setState(() {
                                if (on) {
                                  _rarityFilters.add(r);
                                } else {
                                  _rarityFilters.remove(r);
                                }
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: Text('Possédées $ownedInSet/${_cards.length}'),
                        selected: _ownedOnly,
                        onSelected: (v) => setState(() => _ownedOnly = v),
                      ),
                      if (_rarityOptions.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _openFilterDialog(
                            title: 'Rareté',
                            options: _sortedRarityOptions,
                            selected: _rarityFilters,
                            onApply: (s) => setState(() {
                              _rarityFilters
                                ..clear()
                                ..addAll(s);
                            }),
                          ),
                          icon: const Icon(Icons.star_outline, size: 18),
                          label: Text(
                            _rarityFilters.isEmpty
                                ? 'Toutes raretés'
                                : 'Rareté (${_rarityFilters.length})',
                          ),
                        ),
                      if (_typeOptions.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _openFilterDialog(
                            title: 'Type',
                            options: _typeOptions.toList()..sort(),
                            selected: _typeFilters,
                            onApply: (s) => setState(() {
                              _typeFilters
                                ..clear()
                                ..addAll(s);
                            }),
                          ),
                          icon: const Icon(Icons.bolt_outlined, size: 18),
                          label: Text(
                            _typeFilters.isEmpty
                                ? 'Type'
                                : 'Type (${_typeFilters.length})',
                          ),
                        ),
                    ],
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
                    message: widget.subcategory == CardSubcategory.pokemon
                        ? 'Chargement des cartes et raretés…'
                        : null,
                  )
                : filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.style_outlined,
                        title: _ownedOnly ? 'Aucune possédée' : 'Aucune carte',
                        message: _query.isNotEmpty
                            ? 'Essaie un autre filtre.'
                            : 'Ce set est vide ou le catalogue a échoué.',
                        iconColor: widget.subcategory.color,
                      )
                    : GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.5,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final card = filtered[i];
                          final owned = _ownedIds.contains(card.id);
                          final sel = _selectedIds.contains(card.id);
                          return TcgCatalogCardTile(
                            name: card.name,
                            imageUrl: card.imageUrl,
                            accent: widget.subcategory.color,
                            owned: owned,
                            selectionMode: _bulkMode,
                            selected: sel,
                            onTap: () {
                              if (_bulkMode) {
                                setState(() {
                                  if (sel) {
                                    _selectedIds.remove(card.id);
                                  } else {
                                    _selectedIds.add(card.id);
                                  }
                                });
                              } else {
                                quickAddTcgCatalogCard(
                                  context,
                                  subcategory: widget.subcategory,
                                  card: card,
                                ).then((_) => _refreshOwned());
                              }
                            },
                            onQuickAdd: _bulkMode ? null : () => _quickAddCard(card),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: _bulkMode && _selectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                final picked = filtered
                    .where((c) => _selectedIds.contains(c.id))
                    .toList();
                showBulkAddCardsDialog(
                  context,
                  subcategory: widget.subcategory,
                  cards: picked,
                  onDone: () {
                    setState(() {
                      _bulkMode = false;
                      _selectedIds.clear();
                    });
                    _refreshOwned();
                  },
                );
              },
              backgroundColor: widget.subcategory.color,
              icon: const Icon(Icons.add),
              label: Text('Ajouter ${_selectedIds.length}'),
            )
          : null,
    );
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
                      label: Text(o),
                      selected: tmp.contains(o),
                      onSelected: (on) => setStateDialog(() {
                        if (on) {
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
              onPressed: () => Navigator.pop(ctx, <String>{}),
              child: const Text('Effacer'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, tmp),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
    if (result != null) onApply(result);
  }
}
