import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../services/tmdb_service.dart';
import '../widgets/catalog_search_sheet.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import '../widgets/ui/hub_search_bar.dart';
import 'home_screen.dart';

/// Hub films & séries.
class MovieCollectionScreen extends StatelessWidget {
  const MovieCollectionScreen({super.key});

  static final _accent = Colors.pink.shade700;

  void _openSearch(BuildContext context) {
    showCatalogSearchSheet(
      context,
      title: 'Rechercher un film ou une série',
      hint: 'Titre',
      apiHint: TmdbService.isConfigured
          ? 'Catalogue TMDB'
          : 'Ajoute TMDB_API_KEY dans .env pour la recherche auto',
      search: TmdbService.search,
      onManualEntry: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => const HomeScreen(
              category: CollectionCategory.movie,
              screenTitle: 'Films & séries',
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
            category: CollectionCategory.movie,
            screenTitle: hit['title'] ?? 'Film',
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
            title: 'Films & séries',
            accentColor: _accent,
          ),
          Expanded(
            child: CategoryTypeHub(
              accentColor: _accent,
              title: 'Films & séries',
              showTitleInHero: false,
              subtitle: 'Films et séries TV — catalogue TMDB si clé API.',
              header: HubSearchBar(
                accent: _accent,
                hint: 'Rechercher',
                subtitle: 'Film ou série',
                icon: Icons.movie_outlined,
                onTap: () => _openSearch(context),
              ),
              items: [
                CategoryTypeHubItem(
                  label: 'Ma collection',
                  description: 'Tous mes films & séries',
                  icon: Icons.movie,
                  color: _accent,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => const HomeScreen(
                          category: CollectionCategory.movie,
                          screenTitle: 'Films & séries',
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
