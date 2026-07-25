import '../models/collection_category.dart';
import '../models/collection_item.dart';

/// Objets actuellement possédés (hors wishlist, quantité > 0).
bool isActiveCollectionItem(CollectionItem item) =>
    !item.isWishlist && item.quantity > 0;

/// Candidats pour le tirage aléatoire (shake) — jeux de base uniquement.
bool isShakePickCandidate(CollectionItem item) {
  if (!isActiveCollectionItem(item)) return false;
  if (item.category == CollectionCategory.boardgame) {
    if (item.isExpansion) return false;
    if (item.parentGameId != null && item.parentGameId!.isNotEmpty) {
      return false;
    }
    if (item.metadata?['bgg_is_expansion'] == true) return false;
  }
  return true;
}
