import '../models/collection_item.dart';

/// Statut marketplace d'un exemplaire (vente / échange).
enum MarketplaceDisposition {
  none,
  wantsTrade,
  forSale,
  sold,
}

bool itemWantsTrade(CollectionItem item) =>
    item.metadata?['wants_trade'] == true;

MarketplaceDisposition marketplaceDisposition(CollectionItem item) {
  if (item.isSold) return MarketplaceDisposition.sold;
  if (item.isForSale) return MarketplaceDisposition.forSale;
  if (itemWantsTrade(item)) return MarketplaceDisposition.wantsTrade;
  return MarketplaceDisposition.none;
}

String marketplaceDispositionLabel(MarketplaceDisposition d) => switch (d) {
      MarketplaceDisposition.none => 'Garder',
      MarketplaceDisposition.wantsTrade => 'Recherche d\'échange',
      MarketplaceDisposition.forSale => 'À vendre',
      MarketplaceDisposition.sold => 'Vendu',
    };

Map<String, dynamic> metadataWithWantsTrade(
  Map<String, dynamic>? metadata,
  bool wantsTrade,
) {
  final meta = Map<String, dynamic>.from(metadata ?? {});
  if (wantsTrade) {
    meta['wants_trade'] = true;
  } else {
    meta.remove('wants_trade');
  }
  return meta;
}

bool isMarketplaceListing(CollectionItem item) {
  if (item.isSold || item.isWishlist) return false;
  return item.isForSale || itemWantsTrade(item);
}
