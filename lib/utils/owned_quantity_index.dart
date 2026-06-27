import '../models/collection_item.dart';

/// Clé de rapprochement collection ↔ wishlist (même jeu, scopes différents).
String collectionItemMatchKey(CollectionItem item) {
  final bgg = item.metadata?['bgg_id']?.toString().trim();
  if (bgg != null && bgg.isNotEmpty) return 'bgg:$bgg';
  final sub = item.subcategory ?? '';
  return 'title:${item.title.toLowerCase().trim()}|${item.category.dbValue}|$sub';
}

/// Somme des exemplaires possédés (lignes collection actives, hors wishlist).
Map<String, int> buildOwnedQuantityIndex(Iterable<CollectionItem> items) {
  final map = <String, int>{};
  for (final item in items) {
    if (item.isWishlist || item.isSold) continue;
    final key = collectionItemMatchKey(item);
    map[key] = (map[key] ?? 0) + item.quantity;
  }
  return map;
}

int ownedQuantityFor(CollectionItem item, Map<String, int> index) {
  return index[collectionItemMatchKey(item)] ?? 0;
}
