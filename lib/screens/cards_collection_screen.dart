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

  @override
  void initState() {
    super.initState();
    _maybeShowTip();
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
            'Astuce : « Ma collection » pour voir tes cartes, ou parcours les séries.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  Future<void> _openSubcategory(BuildContext context, CardSubcategory sub) async {
    if (!sub.hasSetBrowser) {
      _openMyCollection(context, sub);
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.collections_bookmark_rounded, color: sub.color),
              title: Text('Ma collection — ${sub.label}'),
              subtitle: const Text('Toutes tes cartes de cet univers'),
              onTap: () => Navigator.pop(ctx, 'mine'),
            ),
            ListTile(
              leading: Icon(Icons.layers_rounded, color: sub.color),
              title: const Text('Parcourir le catalogue'),
              subtitle: const Text('Blocs, séries, cartes possédées x/x'),
              onTap: () => Navigator.pop(ctx, 'browse'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || choice == null) return;
    if (choice == 'mine') {
      _openMyCollection(context, sub);
    } else {
      _openCatalogBrowser(context, sub);
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
          Expanded(
            child: CategoryTypeHub(
              accentColor: _accent,
              title: 'Cartes',
              showTitleInHero: false,
              subtitle:
                  'Ma collection ou parcours par univers — utilise l\'icône recherche dans une collection.',
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
