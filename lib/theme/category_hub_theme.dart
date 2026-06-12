import 'package:flutter/material.dart';

import '../services/lego_catalog_service.dart';
import '../services/movie_catalog_service.dart';
import '../services/videogame_catalog_service.dart';
import '../services/tmdb_service.dart';
import '../services/rawg_service.dart';
import '../services/rebrickable_service.dart';

/// Pastille source affichée sous le sous-titre du hub.
class HubSourceChip {
  final String label;
  final IconData icon;

  const HubSourceChip(this.label, this.icon);
}

/// Identité visuelle d'un hub catalogue (films, jeux, Lego, montres).
class CategoryHubTheme {
  final Color accent;
  final IconData watermarkIcon;
  final String tagline;
  final String searchHint;
  final String searchSubtitle;
  final IconData searchIcon;
  final List<HubSourceChip> sourceChips;

  const CategoryHubTheme({
    required this.accent,
    required this.watermarkIcon,
    required this.tagline,
    required this.searchHint,
    required this.searchSubtitle,
    required this.searchIcon,
    this.sourceChips = const [],
  });

  static CategoryHubTheme movie(Color accent) => CategoryHubTheme(
        accent: accent,
        watermarkIcon: Icons.theaters_rounded,
        tagline:
            'Blu-ray, DVD, steelbooks — films physiques, pas le streaming.',
        searchHint: 'Rechercher un film',
        searchSubtitle: MovieCatalogService.catalogLabel,
        searchIcon: Icons.movie_filter_rounded,
        sourceChips: [
          if (TmdbService.isConfigured)
            const HubSourceChip('TMDB', Icons.movie_outlined),
          const HubSourceChip('iTunes', Icons.play_circle_outline),
        ],
      );

  static CategoryHubTheme videogame(Color accent) => CategoryHubTheme(
        accent: accent,
        watermarkIcon: Icons.sports_esports_rounded,
        tagline: 'Console, PC, rétro — jaquettes et fiches depuis le catalogue.',
        searchHint: 'Rechercher un jeu',
        searchSubtitle: VideogameCatalogService.catalogLabel,
        searchIcon: Icons.videogame_asset_rounded,
        sourceChips: [
          if (RawgService.isConfigured)
            const HubSourceChip('RAWG', Icons.api_rounded),
          const HubSourceChip('Steam', Icons.storefront_rounded),
        ],
      );

  static CategoryHubTheme lego(Color accent) => CategoryHubTheme(
        accent: accent,
        watermarkIcon: Icons.extension_rounded,
        tagline: 'Sets officiels, Creator, maquettes — par n° ou nom de set.',
        searchHint: 'Rechercher un set',
        searchSubtitle: LegoCatalogService.catalogLabel,
        searchIcon: Icons.grid_view_rounded,
        sourceChips: [
          if (RebrickableService.isConfigured)
            const HubSourceChip('Rebrickable', Icons.apps_rounded),
          const HubSourceChip('Wiki Lego', Icons.menu_book_outlined),
        ],
      );

  static CategoryHubTheme watch(Color accent) => CategoryHubTheme(
        accent: accent,
        watermarkIcon: Icons.watch_rounded,
        tagline: 'Marque, modèle, référence — fiches précises pour chaque pièce.',
        searchHint: 'Ajouter une montre',
        searchSubtitle: 'Saisie guidée · pas de catalogue en ligne',
        searchIcon: Icons.watch_outlined,
        sourceChips: const [
          HubSourceChip('Marque & modèle', Icons.edit_outlined),
        ],
      );
}
