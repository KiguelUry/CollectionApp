import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../services/rawg_service.dart';
import '../widgets/catalog_search_sheet.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import '../widgets/ui/hub_search_bar.dart';
import 'home_screen.dart';

/// Hub jeux vidéo.
class VideogameCollectionScreen extends StatelessWidget {
  const VideogameCollectionScreen({super.key});

  static final _accent = Colors.green.shade700;

  void _openSearch(BuildContext context) {
    showCatalogSearchSheet(
      context,
      title: 'Rechercher un jeu',
      hint: 'Nom du jeu',
      apiHint: RawgService.isConfigured
          ? 'Catalogue RAWG'
          : 'Ajoute RAWG_API_KEY dans .env pour la recherche auto',
      search: RawgService.search,
      onManualEntry: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => const HomeScreen(
              category: CollectionCategory.videogame,
              screenTitle: 'Jeux vidéo',
            ),
          ),
        );
      },
    ).then((hit) {
      if (hit == null || !context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => HomeScreen(
            category: CollectionCategory.videogame,
            screenTitle: hit['title'] ?? 'Jeu',
            pendingCatalogHit: hit,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CategoryHubHeader(
            title: 'Jeux vidéo',
            accentColor: _accent,
          ),
          Expanded(
            child: CategoryTypeHub(
              accentColor: _accent,
              title: 'Jeux vidéo',
              showTitleInHero: false,
              subtitle: 'Console, PC, rétro — catalogue RAWG si clé API.',
              header: HubSearchBar(
                accent: _accent,
                hint: 'Rechercher un jeu',
                subtitle: 'Nom du jeu',
                icon: Icons.sports_esports_rounded,
                onTap: () => _openSearch(context),
              ),
              items: [
                CategoryTypeHubItem(
                  label: 'Ma collection',
                  description: 'Tous mes jeux',
                  icon: Icons.sports_esports,
                  color: _accent,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => const HomeScreen(
                          category: CollectionCategory.videogame,
                          screenTitle: 'Jeux vidéo',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
