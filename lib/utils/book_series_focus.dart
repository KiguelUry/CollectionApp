import '../models/collection_item.dart';
import '../models/collection_list_filters.dart';

/// Filtre Focus pour séries livres (volumes perso vs groupes).
abstract final class BookSeriesFocus {
  static List<CollectionItem> filterItems(
    List<CollectionItem> items,
    CollectionListFilters filters,
  ) {
    if (filters.focusGroupId != null && filters.focusGroupId!.isNotEmpty) {
      return items.where((i) => i.groupId == filters.focusGroupId).toList();
    }
    if (filters.ownershipView == CollectionOwnershipView.personal) {
      return items.where((i) => !i.isGroupOwned).toList();
    }
    if (filters.ownershipView == CollectionOwnershipView.groups) {
      if (filters.groupIds.isNotEmpty) {
        return items
            .where((i) => i.groupId != null && filters.groupIds.contains(i.groupId))
            .toList();
      }
      return items.where((i) => i.isGroupOwned).toList();
    }
    return items;
  }

  static bool scopeIsActive(CollectionListFilters filters) =>
      filters.ownershipView != CollectionOwnershipView.all ||
      filters.focusGroupId != null;

  /// Une série est visible si elle a des volumes dans le scope, ou si elle est
  /// vide (structure perso sans tomes liés) en mode Tout / Moi.
  static bool seriesMatchesFocus(
    List<CollectionItem> items,
    CollectionListFilters filters,
  ) {
    if (!scopeIsActive(filters)) return true;

    if (items.isEmpty) {
      return filters.focusGroupId == null &&
          filters.ownershipView != CollectionOwnershipView.groups;
    }

    return filterItems(items, filters).isNotEmpty;
  }
}
