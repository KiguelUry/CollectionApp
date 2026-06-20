/// Service générique « déjà possédé / wishlist » pour un catalogue (Phase 2).
abstract class UserCatalogService {
  Future<Set<String>> ownedCatalogKeys();
  Future<Set<String>> wishlistCatalogKeys();
  Future<bool> removeOwnedByCatalogKey(String catalogKey);
  Future<bool> removeWishlistByCatalogKey(String catalogKey);
}
