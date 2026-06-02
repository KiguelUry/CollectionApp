import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../models/lego_build_kind.dart';
import '../services/rebrickable_service.dart';
import '../widgets/catalog_search_sheet.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import '../widgets/ui/hub_search_bar.dart';
import 'home_screen.dart';

/// Hub Lego & maquettes.
class LegoCollectionScreen extends StatelessWidget {
  const LegoCollectionScreen({super.key});

  static final _accent = Colors.red.shade700;

  void _openSearch(BuildContext context) {
    showCatalogSearchSheet(
      context,
      title: 'Rechercher un set Lego',
      hint: 'Nom ou n° de set (ex: 75192)',
      apiHint: RebrickableService.isConfigured
          ? 'Catalogue Rebrickable'
          : 'Ajoute REBRICKABLE_API_KEY dans .env pour la recherche auto',
      search: RebrickableService.search,
      onManualEntry: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => const HomeScreen(
              category: CollectionCategory.lego,
              screenTitle: 'Lego & maquettes',
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
            category: CollectionCategory.lego,
            screenTitle: hit['title'] ?? 'Lego',
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
            title: 'Lego & maquettes',
            accentColor: _accent,
          ),
          Expanded(
            child: CategoryTypeHub(
              accentColor: _accent,
              title: 'Lego & maquettes',
              showTitleInHero: false,
              subtitle: 'Sets Lego, Creator, maquettes et scale models.',
              header: HubSearchBar(
                accent: _accent,
                hint: 'Rechercher un set',
                subtitle: 'N° ou nom · Rebrickable si clé API',
                icon: Icons.search_rounded,
                onTap: () => _openSearch(context),
              ),
              items: [
                for (final kind in LegoBuildKind.values)
                  CategoryTypeHubItem(
                    label: kind.label,
                    description: kind.description,
                    icon: kind.icon,
                    color: kind.color,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => HomeScreen(
                            category: CollectionCategory.lego,
                            screenTitle: kind.label,
                            fixedLegoKind: kind,
                          ),
                        ),
                      );
                    },
                  ),
              ],
              onClassicList: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => const HomeScreen(
                      category: CollectionCategory.lego,
                      screenTitle: 'Tous les sets',
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
