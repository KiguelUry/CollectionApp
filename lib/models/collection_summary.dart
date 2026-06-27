import '../utils/collection_count_label.dart';

class CollectionSummary {
  /// Objets perso (hors groupe).
  final int ownedCount;
  /// Objets dans un groupe partagé.
  final int groupOwnedCount;
  final int wishlistCount;
  final int pricedItemCount;
  final double totalPurchaseValue;

  const CollectionSummary({
    this.ownedCount = 0,
    this.groupOwnedCount = 0,
    this.wishlistCount = 0,
    this.pricedItemCount = 0,
    this.totalPurchaseValue = 0,
  });

  int get totalOwnedCount => ownedCount + groupOwnedCount;

  bool get hasAnyValue => pricedItemCount > 0;

  /// Ex. « 6 objets dont 5 en groupes »
  String get ownedCountLabel {
    final total = totalOwnedCount;
    return formatCollectionCountLabel(total: total, inGroup: groupOwnedCount);
  }
}
