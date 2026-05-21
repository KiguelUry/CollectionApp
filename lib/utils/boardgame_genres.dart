import '../models/collection_category.dart';
import '../models/collection_item.dart';

/// Genres BGG (`boardgamecategory`) stockés dans `metadata.bgg_categories`.
List<String> boardgameGenresFromMetadata(Map<String, dynamic>? metadata) {
  if (metadata == null) return const [];
  final raw = metadata['bgg_categories'];
  if (raw is List) {
    return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }
  if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
  return const [];
}

String? primaryBoardgameGenre(CollectionItem item) {
  final genres = boardgameGenresFromMetadata(item.metadata);
  return genres.isEmpty ? null : genres.first;
}

/// Tous les genres présents dans une liste de jeux (triés).
List<String> distinctBoardgameGenres(Iterable<CollectionItem> items) {
  final set = <String>{};
  for (final item in items) {
    if (item.category != CollectionCategory.boardgame) continue;
    set.addAll(boardgameGenresFromMetadata(item.metadata));
  }
  final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}
