import 'services/user_catalog_service.dart';

/// État partagé « possédé / wishlist » pour grilles catalogue (Phase 2).
class CatalogOwnedState {
  Set<String> ownedKeys = {};
  Set<String> wishlistKeys = {};

  Future<void> reload(UserCatalogService service) async {
    ownedKeys = await service.ownedCatalogKeys();
    wishlistKeys = await service.wishlistCatalogKeys();
  }

  bool isOwned(String catalogKey) => ownedKeys.contains(catalogKey);

  bool isWishlisted(String catalogKey) => wishlistKeys.contains(catalogKey);
}
