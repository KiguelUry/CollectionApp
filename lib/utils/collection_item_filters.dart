import '../models/collection_item.dart';

/// Objets actuellement dans la collection (hors wishlist, vendus, à vendre).
bool isActiveCollectionItem(CollectionItem item) =>
    !item.isWishlist && !item.isSold && !item.isForSale;

/// Candidats pour le tirage aléatoire (shake).
bool isShakePickCandidate(CollectionItem item) => isActiveCollectionItem(item);
