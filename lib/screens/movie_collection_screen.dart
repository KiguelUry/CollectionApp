import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../services/movie_catalog_service.dart';
import '../theme/category_hub_theme.dart';
import '../widgets/catalog_search_sheet.dart';
import '../widgets/category_catalog_hub_body.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import 'home_screen.dart';

/// Hub films physiques (Blu-ray, DVD, steelbook…).
class MovieCollectionScreen extends StatelessWidget {
  const MovieCollectionScreen({super.key});

  static final _accent = Colors.pink.shade700;
  static final _theme = CategoryHubTheme.movie(_accent);

  void _openSearch(BuildContext context) {
    showCatalogSearchSheet(
      context,
      title: 'Rechercher un film',
      hint: 'Titre (Blu-ray, DVD…)',
      apiHint: MovieCatalogService.catalogLabel,
      search: MovieCatalogService.search,
      accent: _accent,
      onManualEntry: () => _openHome(context),
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

  void _openHome(BuildContext context, {String? screenTitle}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => HomeScreen(
          category: CollectionCategory.movie,
          screenTitle: screenTitle ?? 'Films',
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
          CategoryHubHeader(title: 'Films', accentColor: _accent),
          Expanded(
            child: CategoryCatalogHubBody(
              hubTitle: 'Films',
              theme: _theme,
              onSearch: () => _openSearch(context),
              items: [
                CategoryTypeHubItem(
                  label: 'Ma collection',
                  description: 'Tous mes Blu-ray & DVD',
                  icon: Icons.video_library_rounded,
                  color: _accent,
                  onTap: () => _openHome(context),
                ),
                CategoryTypeHubItem(
                  label: 'Blu-ray',
                  description: 'Films haute définition',
                  icon: Icons.high_quality_rounded,
                  color: Colors.indigo.shade600,
                  onTap: () => _openHome(context, screenTitle: 'Blu-ray'),
                ),
                CategoryTypeHubItem(
                  label: 'DVD & coffrets',
                  description: 'Éditions, steelbooks',
                  icon: Icons.inventory_2_outlined,
                  color: Colors.deepPurple.shade400,
                  onTap: () => _openHome(context, screenTitle: 'DVD & coffrets'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
