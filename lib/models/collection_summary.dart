class CollectionSummary {
  final int ownedCount;
  final int wishlistCount;
  final int pricedItemCount;
  final double totalPurchaseValue;

  const CollectionSummary({
    this.ownedCount = 0,
    this.wishlistCount = 0,
    this.pricedItemCount = 0,
    this.totalPurchaseValue = 0,
  });

  bool get hasAnyValue => pricedItemCount > 0;
}
