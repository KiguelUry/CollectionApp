import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_subcategory.dart';
import '../models/collection_category.dart';
import '../services/lorcast_service.dart';
import '../services/onepiece_tcg_service.dart';
import '../services/pokemon_tcg_service.dart';
import '../services/scryfall_service.dart';
import '../services/ygoprodeck_service.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/card_quick_search_sheet.dart';
import '../widgets/category_type_hub.dart';
import '../widgets/ui/hub_search_bar.dart';
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
            'Astuce : utilise la barre de recherche pour « Dracaufeu », '
            'ou choisis un univers pour parcourir les séries.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  void _openSubcategory(BuildContext context, CardSubcategory sub) {
    if (sub.hasSetBrowser) {
      final loadBlocks = switch (sub) {
        CardSubcategory.pokemon => PokemonTcgService.fetchBlocks,
        CardSubcategory.magic => ScryfallService.fetchBlocks,
        CardSubcategory.yugioh => YgoprodeckService.fetchBlocks,
        CardSubcategory.onepiece => OnepieceTcgService.fetchBlocks,
        CardSubcategory.lorcana => LorcastService.fetchBlocks,
        _ => null,
      };
      if (loadBlocks != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => TcgSeriesBlocksScreen(
              subcategory: sub,
              loadBlocks: loadBlocks,
            ),
          ),
        );
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => HomeScreen(
          category: CollectionCategory.card,
          screenTitle: sub.label,
          fixedCardSubcategory: sub,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Cartes'),
      body: CategoryTypeHub(
        accentColor: _accent,
        title: 'Tes cartes',
        subtitle:
            'Parcours par univers et série, ou cherche une carte en un clin d\'œil.',
        header: HubSearchBar(
          accent: _accent,
          hint: 'Rechercher une carte',
          subtitle: 'Dracaufeu, Charizard, Luffy…',
          icon: Icons.search_rounded,
          onTap: () => showCardQuickSearchSheet(context),
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
        onClassicList: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => const HomeScreen(
                category: CollectionCategory.card,
                screenTitle: 'Toutes les cartes',
              ),
            ),
          );
        },
      ),
    );
  }
}
