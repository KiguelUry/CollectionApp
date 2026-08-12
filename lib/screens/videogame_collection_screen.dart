import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../models/videogame_platform.dart';
import '../services/videogame_catalog_service.dart';
import '../widgets/catalog_search_sheet.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import 'home_screen.dart';
import 'videogame_ranking_screen.dart';

/// Hub jeux vidéo — style proche des jeux de société.
class VideogameCollectionScreen extends StatefulWidget {
  const VideogameCollectionScreen({super.key});

  @override
  State<VideogameCollectionScreen> createState() =>
      _VideogameCollectionScreenState();
}

class _VideogameCollectionScreenState extends State<VideogameCollectionScreen> {
  static final _accent = Colors.green.shade700;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCollection(BuildContext context, {VideogamePlatform? platform}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => HomeScreen(
          category: CollectionCategory.videogame,
          screenTitle: platform?.label ?? 'Mes jeux vidéo',
          accentOverride: _accent,
          fixedVideogamePlatform: platform,
        ),
      ),
    );
  }

  void _openConsoleFilter(BuildContext context) async {
    final platform = await showModalBottomSheet<VideogamePlatform>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Filtrer par console',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in VideogamePlatform.values)
                    if (p != VideogamePlatform.pc)
                      ActionChip(
                        avatar: Icon(p.icon, size: 18),
                        label: Text(p.label),
                        onPressed: () => Navigator.pop(ctx, p),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (platform != null && context.mounted) {
      _openCollection(context, platform: platform);
    }
  }

  void _openRanking(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => const VideogameRankingScreen()),
    );
  }

  void _openSearch(BuildContext context) {
    final q = _searchController.text.trim();
    if (q.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tape au moins 2 lettres pour chercher.'),
        ),
      );
      return;
    }
    showCatalogSearchSheet(
      context,
      title: 'Rechercher un jeu',
      hint: 'Nom du jeu',
      apiHint: VideogameCatalogService.catalogLabel,
      search: VideogameCatalogService.search,
      searchError: () => VideogameCatalogService.lastError,
      accent: _accent,
      initialQuery: q,
      onManualEntry: () => _openCollection(context),
    ).then((hit) {
      if (hit == null || !context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => HomeScreen(
            category: CollectionCategory.videogame,
            screenTitle: hit['title'] ?? 'Jeu',
            accentOverride: _accent,
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
          CategoryHubHeader(title: 'Jeux vidéo', accentColor: _accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _openSearch(context),
              decoration: InputDecoration(
                hintText: 'Rechercher un jeu (RAWG + Steam)',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _openSearch(context),
                ),
              ),
            ),
          ),
          Expanded(
            child: CategoryTypeHub(
              accentColor: _accent,
              title: 'Jeux vidéo',
              showTitleInHero: false,
              heroWatermark: Icons.sports_esports,
              subtitle:
                  'Cherche, note et classe tes jeux — filtre par plateforme dans ta collection.',
              featuredItem: CategoryTypeHubItem(
                label: 'Mes jeux vidéo',
                description: 'Collection et wishlist',
                icon: Icons.view_module_rounded,
                color: _accent,
                onTap: () => _openCollection(context),
              ),
              items: [
                CategoryTypeHubItem(
                  label: 'Mon classement',
                  description: 'Tes notes, avis et % de finition',
                  icon: Icons.emoji_events_rounded,
                  color: Colors.amber.shade800,
                  onTap: () => _openRanking(context),
                ),
                CategoryTypeHubItem(
                  label: 'Rechercher et ajouter',
                  description: VideogameCatalogService.catalogLabel,
                  icon: Icons.travel_explore,
                  color: Colors.blueGrey,
                  onTap: () => _openSearch(context),
                ),
                CategoryTypeHubItem(
                  label: 'PC & Steam',
                  description: 'Filtrer ta collection PC',
                  icon: Icons.computer_rounded,
                  color: Colors.blue.shade700,
                  onTap: () => _openCollection(
                    context,
                    platform: VideogamePlatform.pc,
                  ),
                ),
                CategoryTypeHubItem(
                  label: 'Consoles',
                  description: 'PlayStation, Xbox, Switch…',
                  icon: Icons.gamepad_rounded,
                  color: Colors.orange.shade800,
                  onTap: () => _openConsoleFilter(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
