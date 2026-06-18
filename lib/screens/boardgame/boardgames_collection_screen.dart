import 'package:flutter/material.dart';

import '../../models/collection_category.dart';
import '../../services/boardgame_discovery_service.dart';
import '../../widgets/category_hub_header.dart';
import '../../widgets/category_type_hub.dart';
import '../home_screen.dart';
import 'bgg_catalog_grid_screen.dart';

/// Hub découverte jeux de société (avant la collection perso).
class BoardgamesCollectionScreen extends StatefulWidget {
  const BoardgamesCollectionScreen({super.key});

  @override
  State<BoardgamesCollectionScreen> createState() =>
      _BoardgamesCollectionScreenState();
}

class _BoardgamesCollectionScreenState extends State<BoardgamesCollectionScreen> {
  static const _accent = Colors.orange;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openGrid(
    BuildContext context, {
    required BggCatalogSource source,
    required String title,
    String? query,
    String? genreEn,
    String? genreLabel,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => BggCatalogGridScreen(
          source: source,
          title: title,
          initialQuery: query,
          genreEn: genreEn,
          genreLabel: genreLabel,
        ),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    final q = _searchController.text.trim();
    if (q.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tape au moins 2 lettres pour chercher sur BGG.'),
        ),
      );
      return;
    }
    _openGrid(
      context,
      source: BggCatalogSource.search,
      title: 'Recherche BGG',
      query: q,
    );
  }

  void _openMyCollection(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => const HomeScreen(
          category: CollectionCategory.boardgame,
          screenTitle: 'Mes jeux de société',
          accentOverride: _accent,
        ),
      ),
    );
  }

  void _openGenresPicker(BuildContext context) {
    showModalBottomSheet<void>(
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
                'Explorer par genre',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (en, fr) in boardgameDiscoveryGenres)
                    ActionChip(
                      label: Text(fr),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openGrid(
                          context,
                          source: BggCatalogSource.genre,
                          title: fr,
                          genreEn: en,
                          genreLabel: fr,
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
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
          const CategoryHubHeader(
            title: 'Jeux de société',
            accentColor: _accent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _openSearch(context),
              decoration: InputDecoration(
                hintText: 'Rechercher un jeu (comme « Catan », « Azul »…)',
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
              title: 'Jeux de société',
              showTitleInHero: false,
              heroWatermark: Icons.casino,
              subtitle:
                  'Parcours, découvre et ajoute en un tap — comme pour les cartes.',
              featuredItem: CategoryTypeHubItem(
                label: 'Mes jeux de société',
                description:
                    'Ta collection et ta wishlist — notes, prêts, extensions BGG',
                icon: Icons.view_module_rounded,
                color: _accent,
                onTap: () => _openMyCollection(context),
              ),
              items: [
                CategoryTypeHubItem(
                  label: 'Pour toi',
                  description:
                      'Suggestions selon tes goûts, tes amis et les tendances',
                  icon: Icons.auto_awesome,
                  color: Colors.deepPurple,
                  onTap: () => _openGrid(
                    context,
                    source: BggCatalogSource.forYou,
                    title: 'Pour toi',
                  ),
                ),
                CategoryTypeHubItem(
                  label: 'Populaires',
                  description: 'Les jeux « hot » du moment sur BoardGameGeek',
                  icon: Icons.local_fire_department,
                  color: Colors.red,
                  onTap: () => _openGrid(
                    context,
                    source: BggCatalogSource.popular,
                    title: 'Populaires BGG',
                  ),
                ),
                CategoryTypeHubItem(
                  label: 'Tes amis adorent',
                  description:
                      'Jeux bien notés chez tes amis que tu n\'as pas encore',
                  icon: Icons.people_outline,
                  color: Colors.teal,
                  onTap: () => _openGrid(
                    context,
                    source: BggCatalogSource.friends,
                    title: 'Tes amis adorent',
                  ),
                ),
                CategoryTypeHubItem(
                  label: 'Par genre',
                  description: 'Stratégie, familial, coop, ambiance…',
                  icon: Icons.category_outlined,
                  color: Colors.indigo,
                  onTap: () => _openGenresPicker(context),
                ),
                CategoryTypeHubItem(
                  label: 'Recherche BGG',
                  description: 'Toute la base BoardGameGeek',
                  icon: Icons.travel_explore,
                  color: Colors.blueGrey,
                  onTap: () => _openGrid(
                    context,
                    source: BggCatalogSource.search,
                    title: 'Recherche BGG',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
