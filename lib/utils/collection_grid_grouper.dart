import '../models/collection_item.dart';

/// Regroupe les doublons visuels (même titre + catégorie + groupe).
class GroupedCollectionItem {
  final CollectionItem item;
  final int totalQuantity;
  final List<String> itemIds;

  const GroupedCollectionItem({
    required this.item,
    required this.totalQuantity,
    required this.itemIds,
  });

  bool get hasDuplicates => totalQuantity > 1;
}

class CollectionGridGrouper {
  static String _key(CollectionItem item) {
    final title = item.title.trim().toLowerCase();
    final group = item.groupId ?? 'personal';
    return '${item.category.dbValue}|$title|$group';
  }

  static List<GroupedCollectionItem> group(List<CollectionItem> items) {
    final map = <String, GroupedCollectionItem>{};

    for (final item in items) {
      final key = _key(item);
      final qty = item.quantity;
      if (map.containsKey(key)) {
        final existing = map[key]!;
        map[key] = GroupedCollectionItem(
          item: existing.item,
          totalQuantity: existing.totalQuantity + qty,
          itemIds: [...existing.itemIds, item.id],
        );
      } else {
        map[key] = GroupedCollectionItem(
          item: item,
          totalQuantity: qty,
          itemIds: [item.id],
        );
      }
    }

    return map.values.toList();
  }
}
