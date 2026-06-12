import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../theme/category_hub_theme.dart';
import '../widgets/category_catalog_hub_body.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import '../widgets/watch_quick_search_sheet.dart';
import 'home_screen.dart';

/// Hub montres & bracelets.
class WatchCollectionScreen extends StatelessWidget {
  const WatchCollectionScreen({super.key});

  static final _accent = Colors.blueGrey.shade700;
  static final _theme = CategoryHubTheme.watch(_accent);

  void _openSearch(BuildContext context) {
    showWatchQuickSearchSheet(
      context,
      accent: _accent,
      onManualEntry: () => _openHome(context),
    ).then((hit) {
      if (hit == null || !context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => HomeScreen(
            category: CollectionCategory.watch,
            screenTitle: hit['title'] ?? 'Montre',
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
          category: CollectionCategory.watch,
          screenTitle: screenTitle ?? 'Montres',
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
          CategoryHubHeader(title: 'Montres', accentColor: _accent),
          Expanded(
            child: CategoryCatalogHubBody(
              hubTitle: 'Montres',
              theme: _theme,
              onSearch: () => _openSearch(context),
              items: [
                CategoryTypeHubItem(
                  label: 'Ma collection',
                  description: 'Toutes tes montres',
                  icon: Icons.watch_rounded,
                  color: _accent,
                  onTap: () => _openHome(context),
                ),
                CategoryTypeHubItem(
                  label: 'Habillée',
                  description: 'Classique, habillée',
                  icon: Icons.diamond_outlined,
                  color: Colors.blueGrey.shade900,
                  onTap: () => _openHome(context, screenTitle: 'Habillée'),
                ),
                CategoryTypeHubItem(
                  label: 'Sport & plongée',
                  description: 'Chronographe, diver',
                  icon: Icons.scuba_diving_rounded,
                  color: Colors.teal.shade700,
                  onTap: () => _openHome(context, screenTitle: 'Sport'),
                ),
                CategoryTypeHubItem(
                  label: 'Bracelet & autre',
                  description: 'Accessoires horlogers',
                  icon: Icons.link_rounded,
                  color: Colors.brown.shade600,
                  onTap: () => _openHome(context, screenTitle: 'Accessoires'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
