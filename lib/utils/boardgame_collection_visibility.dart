import '../models/collection_item.dart';
import '../services/boardgame_expansion_service.dart';
import 'boardgame_expansions.dart';

/// Extension liée à un parent → masquée de la grille principale (sauf wishlist / option).
bool isBoardgameHiddenInGlobalCollection(
  CollectionItem item,
  List<CollectionItem> allBoardgames, {
  bool showOwnedExpansions = false,
}) {
  if (item.isWishlist && _itemIsExpansion(item)) return false;
  if (!item.isWishlist && _itemIsExpansion(item)) {
    return !showOwnedExpansions;
  }

  if (BoardgameExpansionService.isHiddenInGlobalList(item)) return true;

  // Legacy : masquer si ce bgg_id est une extension cochée sur un jeu de BASE.
  final bggId = item.metadata?['bgg_id']?.toString();
  if (bggId == null || bggId.isEmpty) return false;

  for (final other in allBoardgames) {
    if (other.id == item.id) continue;
    if (other.isExpansion) continue;
    if (ownedExpansionBggIds(other.metadata).contains(bggId)) return true;
  }
  return false;
}

bool _itemIsExpansion(CollectionItem item) {
  if (item.isExpansion) return true;
  if (item.parentGameId != null && item.parentGameId!.isNotEmpty) return true;
  return item.metadata?['bgg_is_expansion'] == true;
}

String? boardgameExpansionOfLabel(CollectionItem item) {
  return BoardgameExpansionService.orphanExpansionLabel(item);
}
