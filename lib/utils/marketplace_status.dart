import '../models/collection_item.dart';

/// Intention marketplace (ne modifie pas le stock).
enum ItemListingIntent {
  keep,
  wantsTrade,
  forSale,
}

bool itemWantsTrade(CollectionItem item) =>
    item.metadata?['wants_trade'] == true;

ItemListingIntent listingIntent(CollectionItem item) {
  if (item.isForSale) return ItemListingIntent.forSale;
  if (itemWantsTrade(item)) return ItemListingIntent.wantsTrade;
  return ItemListingIntent.keep;
}

String listingIntentLabel(ItemListingIntent intent) => switch (intent) {
      ItemListingIntent.keep => 'Garder',
      ItemListingIntent.wantsTrade => 'À échanger',
      ItemListingIntent.forSale => 'À vendre',
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
  if (item.isWishlist || item.quantity <= 0) return false;
  return item.isForSale || itemWantsTrade(item);
}

/// @deprecated Utiliser [listingIntent] — conservé pour migration douce.
enum MarketplaceDisposition {
  none,
  wantsTrade,
  forSale,
  sold,
}

MarketplaceDisposition marketplaceDisposition(CollectionItem item) {
  if (item.isSold) return MarketplaceDisposition.sold;
  if (item.isForSale) return MarketplaceDisposition.forSale;
  if (itemWantsTrade(item)) return MarketplaceDisposition.wantsTrade;
  return MarketplaceDisposition.none;
}

String marketplaceDispositionLabel(MarketplaceDisposition d) => switch (d) {
      MarketplaceDisposition.none => 'Garder',
      MarketplaceDisposition.wantsTrade => 'À échanger',
      MarketplaceDisposition.forSale => 'À vendre',
      MarketplaceDisposition.sold => 'Vendu',
    };
