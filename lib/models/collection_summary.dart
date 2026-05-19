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

  /// Ex. « 2 objets · 1 en groupe »
  String get ownedCountLabel {
    if (ownedCount == 0 && groupOwnedCount == 0) return '0 objet';
    final parts = <String>[];
    if (ownedCount > 0) {
      parts.add('$ownedCount objet${ownedCount > 1 ? 's' : ''}');
    }
    if (groupOwnedCount > 0) {
      parts.add(
        '$groupOwnedCount en groupe${groupOwnedCount > 1 ? 's' : ''}',
      );
    }
    return parts.join(' · ');
  }
}
