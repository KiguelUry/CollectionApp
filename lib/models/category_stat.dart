import 'collection_category.dart';

class CategoryStat {
  final CollectionCategory category;
  final int itemCount;
  final double purchaseValue;

  const CategoryStat({
    required this.category,
    this.itemCount = 0,
    this.purchaseValue = 0,
  });

  double shareOf(int totalItems) =>
      totalItems == 0 ? 0 : itemCount / totalItems;
}
