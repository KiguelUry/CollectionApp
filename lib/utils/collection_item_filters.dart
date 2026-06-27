import '../models/collection_item.dart';

/// Objets actuellement possédés (hors wishlist, quantité > 0).
bool isActiveCollectionItem(CollectionItem item) =>
    !item.isWishlist && item.quantity > 0;

/// Candidats pour le tirage aléatoire (shake).
bool isShakePickCandidate(CollectionItem item) => isActiveCollectionItem(item);
