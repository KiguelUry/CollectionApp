import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/collection_item_scope.dart';

/// Passe un objet de la wishlist vers la collection possédée.
Future<bool> promoteWishlistToCollection(CollectionItem item) async {
  if (!item.isWishlist || item.id.isEmpty) return false;

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return false;

  await client.from('collection_items').update({
    'is_wishlist': false,
    'quantity': item.quantity < 1 ? 1 : item.quantity,
    'location_user_id': userId,
  }).eq('id', item.id);

  return true;
}

/// Cherche un doublon (même titre / catégorie / scope wishlist).
Future<Map<String, dynamic>?> findDuplicateRow({
  required String title,
  required String categoryDb,
  required bool isWishlist,
  String? subcategory,
  String? groupId,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return null;

  var query = client
      .from('collection_items')
      .select('id, quantity, is_wishlist, title')
      .eq('category', categoryDb)
      .eq('title', title.trim())
      .eq('is_wishlist', isWishlist);

  if (subcategory != null) {
    query = query.eq('subcategory', subcategory);
  }

  if (groupId != null) {
    query = query.eq('group_id', groupId);
  } else {
    query = query
        .filter('group_id', 'is', null)
        .or(CollectionItemScope.personalOrFilter(userId));
  }

  final row = await query.maybeSingle();
  return row == null ? null : Map<String, dynamic>.from(row);
}
