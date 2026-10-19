import '../models/collection_category.dart';
import '../models/collection_item.dart';
import 'bgg_collection_parse.dart';
import 'boardgame_collection_visibility.dart';
import 'collection_item_filters.dart';
import 'item_copy_units.dart';

/// Objets comptés comme « ma collection » : possédés, hors wishlist,
/// extensions masquées, et seulement les catégories actives du hub.
List<CollectionItem> hubOwnedItems(
  List<CollectionItem> items, {
  required Set<CollectionCategory> active,
}) {
  return visibleOwnedLikeGrid(items)
      .where(
        (item) =>
            item.category != CollectionCategory.custom &&
            active.contains(item.category),
      )
      .toList();
}

/// Même ensemble que la grille d'une catégorie : possédés, hors wishlist,
/// hors vendus, extensions masquées comme dans la collection.
List<CollectionItem> visibleOwnedLikeGrid(List<CollectionItem> items) {
  final active = items
      .where((i) => isActiveCollectionItem(i) && !i.isSold)
      .toList();
  final boardgames = active
      .where((i) => i.category == CollectionCategory.boardgame)
      .toList();
  return active
      .where(
        (i) =>
            i.category != CollectionCategory.boardgame ||
            !isBoardgameHiddenInGlobalCollection(i, boardgames),
      )
      .toList();
}

/// Nombre de jeux qui ont au moins un exemplaire en trop
/// (quantité > 1, plusieurs lignes, ou plusieurs boîtes).
int countDuplicateGames(Iterable<CollectionItem> items) {
  final copies = <String, int>{};
  final rows = <String, int>{};
  for (final item in items) {
    final key = normalizeBggImportTitle(item.title);
    if (key.isEmpty) continue;
    final units = readCopyUnits(item);
    final n = units.length >= 2
        ? units.length
        : (item.quantity < 1 ? 1 : item.quantity);
    copies[key] = (copies[key] ?? 0) + n;
    rows[key] = (rows[key] ?? 0) + 1;
  }
  var games = 0;
  for (final key in copies.keys) {
    if (copies[key]! > 1 || (rows[key] ?? 0) > 1) games++;
  }
  return games;
}
