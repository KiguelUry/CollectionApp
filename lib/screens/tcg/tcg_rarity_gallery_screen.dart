import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_set_info.dart';
import '../../services/lorcast_service.dart';
import '../../services/onepiece_tcg_service.dart';
import '../../services/pokemon_tcg_service.dart';
import '../../services/scryfall_service.dart';
import '../../services/ygoprodeck_service.dart';
import '../../utils/tcg_bulk_add.dart';
import '../../utils/tcg_rarity_order.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/tcg/tcg_catalog_card_tile.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/loading_placeholder.dart';

/// Toutes les cartes d'un bloc ou d'une série filtrées par rareté.
class TcgRarityGalleryScreen extends StatefulWidget {
  final CardSubcategory subcategory;
  final String title;
  final List<TcgSetInfo> sets;
  final TcgSetInfo? singleSet;

  const TcgRarityGalleryScreen({
    super.key,
    required this.subcategory,
    required this.title,
    required this.sets,
    this.singleSet,
  });

  @override
  State<TcgRarityGalleryScreen> createState() => _TcgRarityGalleryScreenState();
}

class _TcgRarityGalleryScreenState extends State<TcgRarityGalleryScreen> {
  final List<TcgCatalogCard> _all = [];
  bool _loading = true;
  String? _selectedRarity;
  bool _bulkMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<TcgCatalogCard>> _fetchSet(TcgSetInfo set) async {
    return switch (widget.subcategory) {
      CardSubcategory.pokemon => PokemonTcgService.fetchCardsInSet(set.id),
      CardSubcategory.magic =>
        ScryfallService.fetchCardsInSet(set.code ?? set.id),
      CardSubcategory.yugioh => YgoprodeckService.fetchCardsInSet(set.name),
      CardSubcategory.onepiece => OnepieceTcgService.fetchCardsInSet(set.id),
      CardSubcategory.lorcana => LorcastService.fetchCardsInSet(set.id),
      _ => [],
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _all.clear();
    final targets =
        widget.singleSet != null ? [widget.singleSet!] : widget.sets;

    final batches = await Future.wait(targets.map(_fetchSet));
    if (!mounted) return;
    for (final cards in batches) {
      _all.addAll(cards);
    }

    setState(() => _loading = false);
  }

  Set<String> get _rarities {
    final r = <String>{};
    for (final c in _all) {
      final v = c.rarity?.trim();
      if (v != null && v.isNotEmpty) r.add(v);
    }
    return r;
  }

  List<TcgCatalogCard> get _filtered {
    if (_selectedRarity == null) return [];
    return _all
        .where(
          (c) =>
              c.rarity != null &&
              c.rarity!.toLowerCase() == _selectedRarity!.toLowerCase(),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final rarities = sortRarityLabels(_rarities.toList(), widget.subcategory);

    return Scaffold(
      appBar: AppAppBar(
        title: widget.title,
        actions: [
          if (_filtered.isNotEmpty)
            IconButton(
              tooltip: _bulkMode ? 'Annuler sélection' : 'Ajout rapide',
              icon: Icon(_bulkMode ? Icons.close : Icons.playlist_add_check),
              onPressed: () => setState(() {
                _bulkMode = !_bulkMode;
                _selectedIds.clear();
              }),
            ),
        ],
      ),
      body: Column(
        children: [
          if (rarities.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  for (final r in rarities)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(r, style: const TextStyle(fontSize: 11)),
                        selected: _selectedRarity == r,
                        onSelected: (_) => setState(() => _selectedRarity = r),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const LoadingPlaceholder(grid: true, count: 12)
                : _selectedRarity == null
                    ? const EmptyState(
                        icon: Icons.star_outline,
                        title: 'Choisis une rareté',
                        message: 'Affiche toutes les cartes de ce niveau.',
                      )
                    : _filtered.isEmpty
                        ? const EmptyState(
                            icon: Icons.style_outlined,
                            title: 'Aucune carte',
                            message: 'Pas de carte avec cette rareté ici.',
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.5,
                              crossAxisSpacing: 4,
                              mainAxisSpacing: 4,
                            ),
                            itemCount: _filtered.length,
                            itemBuilder: (context, i) {
                              final card = _filtered[i];
                              final sel = _selectedIds.contains(card.id);
                              return TcgCatalogCardTile(
                                name: card.name,
                                imageUrl: card.imageUrl,
                                accent: widget.subcategory.color,
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
                                    silentAddTcgCard(
                                      context,
                                      subcategory: widget.subcategory,
                                      card: card,
                                    ).then((ok) {
                                      if (ok && mounted) _load();
                                    });
                                  }
                                },
                                onQuickAdd: _bulkMode
                                    ? null
                                    : () => silentAddTcgCard(
                                          context,
                                          subcategory: widget.subcategory,
                                          card: card,
                                        ).then((ok) {
                                          if (ok && mounted) _load();
                                        }),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: _bulkMode && _selectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                final cards = _filtered
                    .where((c) => _selectedIds.contains(c.id))
                    .toList();
                showBulkAddCardsDialog(
                  context,
                  subcategory: widget.subcategory,
                  cards: cards,
                  onDone: () {
                    setState(() {
                      _bulkMode = false;
                      _selectedIds.clear();
                    });
                    _load();
                  },
                );
              },
              icon: const Icon(Icons.add),
              label: Text('Ajouter ${_selectedIds.length}'),
            )
          : null,
    );
  }
}
