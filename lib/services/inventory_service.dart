import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_item_scope.dart';

class InventoryService {
  final _client = Supabase.instance.client;

  static const _select =
      '*, locations(label), groups(name)';

  Future<List<CollectionItem>> _fetchAll() async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return [];

    final rows = await CollectionItemScope.personal(
      _client.from('collection_items').select(_select),
      userId: userId,
    );
    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Doublons : même titre + catégorie, ou quantité > 1 (hors wishlist / vendus).
  Future<List<GroupedCollectionItem>> fetchDuplicates() async {
    final items = (await _fetchAll())
        .where((i) => !i.isWishlist && !i.isSold)
        .toList();
    return CollectionGridGrouper.group(items)
        .where((g) => g.hasDuplicates)
        .toList();
  }

  Future<List<CollectionItem>> fetchForSale() async {
    return (await _fetchAll())
        .where((i) => i.isForSale && !i.isSold && !i.isWishlist)
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<List<CollectionItem>> fetchSold() async {
    return (await _fetchAll())
        .where((i) => i.isSold)
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<void> setForSale(String itemId, bool value) async {
    await _client.from('collection_items').update({
      'is_for_sale': value,
      if (value) 'is_sold': false,
    }).eq('id', itemId);
  }

  Future<void> setSold(String itemId, bool value) async {
    await _client.from('collection_items').update({
      'is_sold': value,
      if (value) 'is_for_sale': false,
    }).eq('id', itemId);
  }
}
