import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../services/collection_refresh.dart';
import '../utils/collection_item_scope.dart';
import '../utils/whereabouts_apply.dart';
import '../utils/whereabouts_persistence.dart';

/// Passe un objet de la wishlist vers la collection possédée.
///
/// - `is_wishlist` → false
/// - quantité au moins 1
/// - localisation « Chez moi » (détenteur = utilisateur courant)
Future<bool> promoteWishlistToCollection(CollectionItem item) async {
  if (!item.isWishlist || item.id.isEmpty) return false;

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return false;

  final qty = item.quantity < 1 ? 1 : item.quantity.clamp(1, 9999);
  final atHome = applyWhereaboutsChange(
    item.copyWith(isWishlist: false, quantity: qty),
    locationUserId: userId,
    holderLabel: 'Chez moi',
  );

  final groupIds = item.groupId != null && item.groupId!.isNotEmpty
      ? [item.groupId!]
      : <String>[];
  final whereabouts = buildWhereaboutsDbFields(
    atHome,
    groupIds: groupIds.isEmpty ? null : groupIds,
  );
  var meta = Map<String, dynamic>.from(
    whereabouts['metadata'] as Map<String, dynamic>,
  );
  meta = finalizeMetadataPayload(atHome, meta);

  await client.from('collection_items').update({
    'is_wishlist': false,
    'quantity': qty,
    'location_user_id': whereabouts['location_user_id'],
    'metadata': meta,
  }).eq('id', item.id);

  CollectionRefresh.instance.bump();
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
