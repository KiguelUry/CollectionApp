import '../models/collection_item.dart';
import 'boardgame_expansions.dart';

/// Extension enregistrée sur le jeu de base → masquée de la grille principale.
bool isBoardgameHiddenInGlobalCollection(
  CollectionItem item,
  List<CollectionItem> allBoardgames,
) {
  final bggId = item.metadata?['bgg_id']?.toString();
  if (bggId == null || bggId.isEmpty) return false;

  for (final other in allBoardgames) {
    if (other.id == item.id) continue;
    if (ownedExpansionBggIds(other.metadata).contains(bggId)) return true;
  }
  return false;
}

String? boardgameExpansionOfLabel(CollectionItem item) {
  final title = item.metadata?['expansion_of_title']?.toString();
  if (title != null && title.isNotEmpty) return title;
  return null;
}
