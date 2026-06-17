import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_subcategory.dart';
import '../models/collection_category.dart';
import '../services/lorcast_service.dart';
import '../services/onepiece_tcg_service.dart';
import '../services/pokemon_tcg_service.dart';
import '../services/scryfall_service.dart';
import '../services/ygoprodeck_service.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import 'home_screen.dart';
import 'tcg/tcg_global_search_screen.dart';
import 'tcg/tcg_series_blocks_screen.dart';

/// Hub Cartes : univers populaires → navigateur de séries ou liste classique.
class CardsCollectionScreen extends StatefulWidget {
  const CardsCollectionScreen({super.key});

  @override
  State<CardsCollectionScreen> createState() => _CardsCollectionScreenState();
}

class _CardsCollectionScreenState extends State<CardsCollectionScreen> {
  static const _accent = Color(0xFFE65100);
  static const _tipKey = 'ux_tip_cards_hub';

  CardSubcategory _searchSub = CardSubcategory.pokemon;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _maybeShowTip();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openGlobalSearch(BuildContext context) {
    final q = _searchController.text.trim();
    if (q.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tape au moins 2 lettres pour lancer la recherche.'),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => TcgGlobalSearchScreen(
          subcategory: _searchSub,
          query: q,
        ),
      ),
    );
  }

  Future<void> _maybeShowTip() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_tipKey) == true) return;
    await prefs.setBool(_tipKey, true);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text(
            'Astuce : « Toutes mes cartes » pour ta collection, ou parcours les séries par univers.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  void _openSubcategory(BuildContext context, CardSubcategory sub) {
    if (sub.hasSetBrowser) {
      _openCatalogBrowser(context, sub);
    } else {
      _openMyCollection(context, sub);
    }
  }

  void _openMyCollection(BuildContext context, CardSubcategory sub) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => HomeScreen(
          category: CollectionCategory.card,
          screenTitle: sub.label,
          fixedCardSubcategory: sub,
          accentOverride: _accent,
        ),
      ),
    );
  }

  void _openCatalogBrowser(BuildContext context, CardSubcategory sub) {
    final loadBlocks = switch (sub) {
      CardSubcategory.pokemon => PokemonTcgService.fetchBlocks,
      CardSubcategory.magic => ScryfallService.fetchBlocks,
      CardSubcategory.yugioh => YgoprodeckService.fetchBlocks,
      CardSubcategory.onepiece => OnepieceTcgService.fetchBlocks,
      CardSubcategory.lorcana => LorcastService.fetchBlocks,
      _ => null,
    };
    if (loadBlocks == null) {
      _openMyCollection(context, sub);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => TcgSeriesBlocksScreen(
          subcategory: sub,
          loadBlocks: loadBlocks,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CategoryHubHeader(
            title: 'Cartes',
            accentColor: _accent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final sub in CardSubcategory.hubOrder.where(
                        (s) => s.supportsCatalogSearch,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(
                              sub.label,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _searchSub == sub,
                            onSelected: (_) =>
                                setState(() => _searchSub = sub),
                            avatar: Icon(sub.icon, size: 16, color: sub.color),
                            showCheckmark: false,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _openGlobalSearch(context),
                  decoration: InputDecoration(
                    hintText: _searchSub == CardSubcategory.pokemon
                        ? 'Rechercher « dracaufeu » dans Pokémon…'
                        : 'Rechercher une carte dans ${_searchSub.label}…',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => _openGlobalSearch(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: CategoryTypeHub(
              accentColor: _accent,
              title: 'Cartes',
              showTitleInHero: false,
              subtitle:
                  'Recherche globale ci-dessus, ou parcours par univers.',
              featuredItem: CategoryTypeHubItem(
                label: 'Toutes mes cartes',
                description: 'Vue globale — filtre par univers (Pokémon, One Piece…)',
                icon: Icons.view_module_rounded,
                color: _accent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const HomeScreen(
                        category: CollectionCategory.card,
                        screenTitle: 'Toutes les cartes',
                        accentOverride: _accent,
                      ),
                    ),
                  );
                },
              ),
              items: [
                for (final sub in CardSubcategory.hubOrder)
                  CategoryTypeHubItem(
                    label: sub.label,
                    description: sub.description,
                    icon: sub.icon,
                    color: sub.color,
                    onTap: () => _openSubcategory(context, sub),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
