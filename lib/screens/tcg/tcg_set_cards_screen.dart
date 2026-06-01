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
import '../../widgets/app_app_bar.dart';
import '../../widgets/bgg_network_image.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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

  List<TcgCatalogCard> get _filtered {
    var list = _cards;
    if (_ownedOnly) {
      list = list.where((c) => _ownedIds.contains(c.id)).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

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
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Filtrer…',
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                FilterChip(
                  label: Text('Possédées ($ownedInSet/${_cards.length})'),
                  selected: _ownedOnly,
                  onSelected: (v) => setState(() => _ownedOnly = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingPlaceholder(grid: false, count: 8)
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
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.62,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final card = filtered[i];
                          final owned = _ownedIds.contains(card.id);
                          return InkWell(
                            onTap: () => quickAddTcgCatalogCard(
                              context,
                              subcategory: widget.subcategory,
                              card: card,
                            ),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (card.imageUrl != null &&
                                      card.imageUrl!.isNotEmpty)
                                    BggNetworkImage(url: card.imageUrl!)
                                  else
                                    ColoredBox(
                                      color: Colors.grey.shade200,
                                      child: Icon(
                                        Icons.style,
                                        color: widget.subcategory.color,
                                      ),
                                    ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      color: Colors.black54,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 3,
                                      ),
                                      child: Text(
                                        card.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (owned)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade600,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
