import 'package:flutter/material.dart';

import '../models/category_metadata.dart';
import '../models/collection_category.dart';
import '../models/media_format_ui.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/category_type_hub.dart';
import '../widgets/media_quick_search_sheet.dart';
import '../widgets/ui/hub_search_bar.dart';
import 'home_screen.dart';

/// Hub Vinyles / CD / K7.
class MediaCollectionScreen extends StatelessWidget {
  const MediaCollectionScreen({super.key});

  static final _accent = Colors.teal.shade700;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Vinyles / CD'),
      body: CategoryTypeHub(
        accentColor: _accent,
        title: 'Vinyles & musique',
        subtitle:
            'Discogs pour les vinyles (avec token) · MusicBrainz en secours.',
        header: HubSearchBar(
          accent: _accent,
          hint: 'Rechercher un album',
          subtitle: 'Artiste, titre, scan EAN…',
          icon: Icons.album_rounded,
          onTap: () => showMediaQuickSearchSheet(context),
        ),
        items: [
          for (final format in MediaFormat.values)
            CategoryTypeHubItem(
              label: format.label,
              description: format.description,
              icon: format.icon,
              color: format.color,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => HomeScreen(
                      category: CollectionCategory.media,
                      screenTitle: format.label,
                      fixedMediaFormat: format,
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
                category: CollectionCategory.media,
                screenTitle: 'Tous les albums',
              ),
            ),
          );
        },
      ),
    );
  }
}
