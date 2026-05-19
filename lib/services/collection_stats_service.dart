import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category_stat.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../models/collection_summary.dart';
import '../utils/collection_item_filters.dart';
import '../utils/collection_item_scope.dart';

class CollectionStatsService {
  final _client = Supabase.instance.client;

  Future<CollectionSummary> fetchSummary() async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return const CollectionSummary();

    final rows = await CollectionItemScope.personal(
      _client.from('collection_items').select(
        'purchase_price, quantity, is_wishlist, is_sold, is_for_sale',
      ),
      userId: userId,
    );

    var owned = 0;
    var wishlist = 0;
    var priced = 0;
    var total = 0.0;

    for (final row in rows as List) {
      final isWishlist = row['is_wishlist'] as bool? ?? false;
      final isSold = row['is_sold'] as bool? ?? false;
      final isForSale = row['is_for_sale'] as bool? ?? false;
      if (isWishlist) {
        wishlist++;
        continue;
      }
      if (isSold || isForSale) continue;

      owned++;
      final price = row['purchase_price'];
      if (price == null) continue;

      final unit = price is num ? price.toDouble() : double.tryParse('$price');
      if (unit == null) continue;

      final qty = (row['quantity'] as int?) ?? 1;
      priced++;
      total += unit * qty;
    }

    var groupOwned = 0;
    final memberRows = await _client
        .from('group_members')
        .select('group_id')
        .eq('profile_id', userId);
    final groupIds = (memberRows as List)
        .map((r) => r['group_id'] as String)
        .toList();
    if (groupIds.isNotEmpty) {
      final gRows = await _client
          .from('collection_items')
          .select('is_wishlist, is_sold, is_for_sale')
          .inFilter('group_id', groupIds);
      for (final row in gRows as List) {
        final isWishlist = row['is_wishlist'] as bool? ?? false;
        final isSold = row['is_sold'] as bool? ?? false;
        final isForSale = row['is_for_sale'] as bool? ?? false;
        if (!isWishlist && !isSold && !isForSale) groupOwned++;
      }
    }

    return CollectionSummary(
      ownedCount: owned,
      groupOwnedCount: groupOwned,
      wishlistCount: wishlist,
      pricedItemCount: priced,
      totalPurchaseValue: total,
    );
  }

  Future<Map<CollectionCategory, List<CollectionItem>>> fetchWishlistByCategory() async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return {};

    final rows = await CollectionItemScope.personal(
      _client.from('collection_items').select().eq('is_wishlist', true),
      userId: userId,
    ).order('title');

    final map = {
      for (final c in CollectionCategory.values) c: <CollectionItem>[],
    };

    for (final row in rows as List) {
      final item = CollectionItem.fromJson(Map<String, dynamic>.from(row));
      map[item.category]?.add(item);
    }

    map.removeWhere((_, list) => list.isEmpty);
    return map;
  }

  /// Répartition par catégorie (collection active).
  Future<List<CategoryStat>> fetchCategoryStats() async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return [];

    final rows = await CollectionItemScope.personal(
      _client.from('collection_items').select(
        'category, quantity, purchase_price, is_wishlist, is_sold, is_for_sale',
      ),
      userId: userId,
    );

    final map = {
      for (final c in CollectionCategory.values)
        c: CategoryStat(category: c),
    };

    for (final row in rows as List) {
      final isWishlist = row['is_wishlist'] as bool? ?? false;
      final isSold = row['is_sold'] as bool? ?? false;
      final isForSale = row['is_for_sale'] as bool? ?? false;
      if (isWishlist || isSold || isForSale) continue;

      final cat = CollectionCategory.fromDbValue(row['category'] as String);
      final qty = (row['quantity'] as int?) ?? 1;
      final price = row['purchase_price'];
      var value = 0.0;
      if (price is num) value = price.toDouble() * qty;

      final prev = map[cat]!;
      map[cat] = CategoryStat(
        category: cat,
        itemCount: prev.itemCount + qty,
        purchaseValue: prev.purchaseValue + value,
      );
    }

    final list = map.values.where((s) => s.itemCount > 0).toList();
    list.sort((a, b) => b.itemCount.compareTo(a.itemCount));
    return list;
  }

  /// Objets les plus chers (prix d'achat renseigné).
  Future<List<CollectionItem>> fetchTopValuedItems({int limit = 8}) async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return [];

    final rows = await CollectionItemScope.personal(
      _client
          .from('collection_items')
          .select()
          .not('purchase_price', 'is', null)
          .eq('is_wishlist', false)
          .eq('is_sold', false)
          .eq('is_for_sale', false),
      userId: userId,
    );

    final items = (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .where(isActiveCollectionItem)
        .toList();

    items.sort((a, b) {
      final va = (a.purchasePrice ?? 0) * a.quantity;
      final vb = (b.purchasePrice ?? 0) * b.quantity;
      return vb.compareTo(va);
    });

    return items.take(limit).toList();
  }
}
