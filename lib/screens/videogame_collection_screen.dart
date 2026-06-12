import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../services/videogame_catalog_service.dart';
import '../theme/category_hub_theme.dart';
import '../widgets/catalog_search_sheet.dart';
import '../widgets/category_catalog_hub_body.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import 'home_screen.dart';

/// Hub jeux vidéo.
class VideogameCollectionScreen extends StatelessWidget {
  const VideogameCollectionScreen({super.key});

  static final _accent = Colors.green.shade700;
  static final _theme = CategoryHubTheme.videogame(_accent);

  void _openSearch(BuildContext context) {
    showCatalogSearchSheet(
      context,
      title: 'Rechercher un jeu',
      hint: 'Nom du jeu',
      apiHint: VideogameCatalogService.catalogLabel,
      search: VideogameCatalogService.search,
      accent: _accent,
      onManualEntry: () => _openHome(context),
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

  void _openHome(BuildContext context, {String? screenTitle}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => HomeScreen(
          category: CollectionCategory.videogame,
          screenTitle: screenTitle ?? 'Jeux vidéo',
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
          CategoryHubHeader(title: 'Jeux vidéo', accentColor: _accent),
          Expanded(
            child: CategoryCatalogHubBody(
              hubTitle: 'Jeux vidéo',
              theme: _theme,
              onSearch: () => _openSearch(context),
              onClassicList: () => _openHome(context),
              items: [
                CategoryTypeHubItem(
                  label: 'Ma collection',
                  description: 'Tous mes jeux',
                  icon: Icons.sports_esports_rounded,
                  color: _accent,
                  onTap: () => _openHome(context),
                ),
                CategoryTypeHubItem(
                  label: 'Console',
                  description: 'PlayStation, Xbox, Switch…',
                  icon: Icons.gamepad_rounded,
                  color: Colors.orange.shade800,
                  onTap: () => _openHome(context, screenTitle: 'Console'),
                ),
                CategoryTypeHubItem(
                  label: 'PC',
                  description: 'Steam, GOG, boîte',
                  icon: Icons.computer_rounded,
                  color: Colors.blue.shade700,
                  onTap: () => _openHome(context, screenTitle: 'PC'),
                ),
                CategoryTypeHubItem(
                  label: 'Rétro',
                  description: 'Anciennes générations',
                  icon: Icons.history_rounded,
                  color: Colors.purple.shade600,
                  onTap: () => _openHome(context, screenTitle: 'Rétro'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
