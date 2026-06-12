import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../models/lego_build_kind.dart';
import '../services/lego_catalog_service.dart';
import '../theme/category_hub_theme.dart';
import '../widgets/catalog_search_sheet.dart';
import '../widgets/category_catalog_hub_body.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import 'home_screen.dart';

/// Hub Lego & maquettes.
class LegoCollectionScreen extends StatelessWidget {
  const LegoCollectionScreen({super.key});

  static final _accent = Colors.red.shade700;
  static final _theme = CategoryHubTheme.lego(_accent);

  void _openSearch(BuildContext context) {
    showCatalogSearchSheet(
      context,
      title: 'Rechercher un set Lego',
      hint: 'Nom ou n° de set (ex: 75192)',
      apiHint: LegoCatalogService.catalogLabel,
      search: LegoCatalogService.search,
      accent: _accent,
      onManualEntry: () => _openHome(context),
    ).then((hit) {
      if (hit == null || !context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => HomeScreen(
            category: CollectionCategory.lego,
            screenTitle: hit['title'] ?? 'Lego',
            pendingCatalogHit: hit,
          ),
        ),
      );
    });
  }

  void _openHome(BuildContext context, {String? screenTitle, LegoBuildKind? kind}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => HomeScreen(
          category: CollectionCategory.lego,
          screenTitle: screenTitle ?? 'Lego & maquettes',
          fixedLegoKind: kind,
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
            title: 'Lego & maquettes',
            accentColor: _accent,
          ),
          Expanded(
            child: CategoryCatalogHubBody(
              hubTitle: 'Lego & maquettes',
              theme: _theme,
              onSearch: () => _openSearch(context),
              onClassicList: () => _openHome(context, screenTitle: 'Tous les sets'),
              items: [
                for (final kind in LegoBuildKind.values)
                  CategoryTypeHubItem(
                    label: kind.label,
                    description: kind.description,
                    icon: kind.icon,
                    color: kind.color,
                    onTap: () => _openHome(context, screenTitle: kind.label, kind: kind),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
