import '../models/collection_category.dart';
import '../models/videogame_platform.dart';

/// Métadonnées Supabase à partir d'un résultat de recherche catalogue.
Map<String, dynamic> metadataFromCatalogHit(
  Map<String, String> hit,
  CollectionCategory category,
) {
  return switch (category) {
    CollectionCategory.lego => {
        if (hit['set_number']?.isNotEmpty == true)
          'set_number': hit['set_number'],
        if (hit['piece_count']?.isNotEmpty == true)
          'piece_count': int.tryParse(hit['piece_count']!),
        if (hit['year']?.isNotEmpty == true) 'year': hit['year'],
        if (hit['rebrickable_id']?.isNotEmpty == true)
          'rebrickable_id': hit['rebrickable_id'],
        'lego_kind': 'lego',
        'source': hit['source'] ?? 'rebrickable',
      },
    CollectionCategory.videogame => {
        if (hit['platform']?.isNotEmpty == true) 'platform': hit['platform'],
        if (hit['year']?.isNotEmpty == true) 'year': hit['year'],
        if (hit['rawg_id']?.isNotEmpty == true) 'rawg_id': hit['rawg_id'],
        if (hit['steam_appid']?.isNotEmpty == true)
          'steam_appid': hit['steam_appid'],
        if (hit['rawg_rating']?.isNotEmpty == true)
          'rawg_rating': hit['rawg_rating'],
        if (hit['summary']?.isNotEmpty == true) 'summary': hit['summary'],
        'source': hit['source'] ?? 'rawg',
        ...() {
          final inferred =
              VideogamePlatform.inferFromText(hit['platform']);
          if (inferred.isEmpty) return <String, dynamic>{};
          return {
            'platform_ids': inferred.map((p) => p.id).toList(),
          };
        }(),
      },
    CollectionCategory.movie => {
        'media_kind': 'movie',
        'physical_format': hit['physical_format'] ?? 'physical',
        if (hit['year']?.isNotEmpty == true) 'year': hit['year'],
        if (hit['tmdb_id']?.isNotEmpty == true) 'tmdb_id': hit['tmdb_id'],
        if (hit['itunes_id']?.isNotEmpty == true) 'itunes_id': hit['itunes_id'],
        'source': hit['source'] ?? 'tmdb',
      },
    CollectionCategory.watch => {
        if (hit['brand']?.isNotEmpty == true) 'brand': hit['brand'],
        if (hit['model']?.isNotEmpty == true) 'model': hit['model'],
        if (hit['reference']?.isNotEmpty == true) 'reference': hit['reference'],
        'source': hit['source'] ?? 'manual_watch',
      },
    _ => <String, dynamic>{},
  };
}
