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
/// - localisation (défaut « Chez moi ») et groupe optionnels
Future<bool> promoteWishlistToCollection(
  CollectionItem item, {
  String? locationUserId,
  String? holderLabel,
  String? groupId,
  int? quantity,
}) async {
  if (!item.isWishlist || item.id.isEmpty) return false;

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return false;

  final qty = (quantity ?? (item.quantity < 1 ? 1 : item.quantity)).clamp(1, 9999);
  final promoted = applyWhereaboutsChange(
    item.copyWith(isWishlist: false, quantity: qty),
    locationUserId: locationUserId ?? userId,
    holderLabel: holderLabel ?? 'Chez moi',
  );

  final resolvedGroup = groupId ?? item.groupId;
  final groupIds = resolvedGroup != null && resolvedGroup.isNotEmpty
      ? [resolvedGroup]
      : <String>[];
  final whereabouts = buildWhereaboutsDbFields(
    promoted,
    groupIds: groupIds.isEmpty ? null : groupIds,
  );
  var meta = Map<String, dynamic>.from(
    whereabouts['metadata'] as Map<String, dynamic>,
  );
  meta = finalizeMetadataPayload(promoted, meta);

  await client.from('collection_items').update({
    'is_wishlist': false,
    'quantity': qty,
    'location_user_id': whereabouts['location_user_id'],
    'group_id': groupIds.isEmpty ? null : groupIds.first,
    'metadata': meta,
  }).eq('id', item.id);

  CollectionRefresh.instance.bump();
  return true;
}

/// Cherche un doublon wishlist par `bgg_id` (ou autre id externe) puis titre.
Future<Map<String, dynamic>?> findWishlistDuplicate({
  required String title,
  required String categoryDb,
  String? bggId,
  String? subcategory,
  String? groupId,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return null;

  final normalizedTitle = title.trim().toLowerCase();

  var base = client
      .from('collection_items')
      .select('id, quantity, is_wishlist, title, metadata')
      .eq('category', categoryDb)
      .eq('is_wishlist', true);

  if (subcategory != null) {
    base = base.eq('subcategory', subcategory);
  }
  if (groupId != null && groupId.isNotEmpty) {
    base = base.eq('group_id', groupId);
  } else {
    base = base
        .filter('group_id', 'is', null)
        .or(CollectionItemScope.personalOrFilter(userId));
  }

  final rows = await base.limit(200);
  final list = (rows as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  final externalId = bggId?.trim();
  if (externalId != null && externalId.isNotEmpty) {
    for (final row in list) {
      final meta = row['metadata'];
      final id = meta is Map ? meta['bgg_id']?.toString().trim() : null;
      if (id != null && id == externalId) return row;
    }
  }

  for (final row in list) {
    final t = row['title']?.toString().trim().toLowerCase() ?? '';
    if (t == normalizedTitle) return row;
  }
  return null;
}

/// Cherche un doublon (même titre / catégorie / scope wishlist).
Future<Map<String, dynamic>?> findDuplicateRow({
  required String title,
  required String categoryDb,
  required bool isWishlist,
  String? subcategory,
  String? groupId,
  String? bggId,
}) async {
  if (isWishlist) {
    return findWishlistDuplicate(
      title: title,
      categoryDb: categoryDb,
      bggId: bggId,
      subcategory: subcategory,
      groupId: groupId,
    );
  }

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
