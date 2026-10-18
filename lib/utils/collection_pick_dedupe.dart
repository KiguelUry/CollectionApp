import '../models/collection_item.dart';
import 'bgg_collection_parse.dart';

/// Liste « choix de jeu » sans doublons (id, bgg_id, titre normalisé).
List<CollectionItem> dedupeCollectionItemsForPick(
  Iterable<CollectionItem> items,
) {
  final seenIds = <String>{};
  final seenBgg = <String>{};
  final seenTitles = <String>{};
  final out = <CollectionItem>[];

  for (final item in items) {
    if (item.id.isNotEmpty && !seenIds.add(item.id)) continue;

    final bgg = item.metadata?['bgg_id']?.toString().trim();
    if (bgg != null && bgg.isNotEmpty) {
      if (!seenBgg.add(bgg)) continue;
    }

    final titleKey = normalizeBggImportTitle(item.title);
    if (titleKey.isNotEmpty && !seenTitles.add(titleKey)) continue;

    out.add(item);
  }
  return out;
}
