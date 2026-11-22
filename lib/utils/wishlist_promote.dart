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
      .select(
        'id, quantity, is_wishlist, title, bgg_id:metadata->>bgg_id, '
        'original_title:metadata->>original_title',
      )
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

  return matchCatalogDuplicate(list, title: normalizedTitle, bggId: bggId);
}

/// Objet déjà possédé (perso ou ajouté par moi dans un groupe), par `bgg_id`
/// puis titre affiché / titre d'origine.
Future<Map<String, dynamic>?> findOwnedDuplicate({
  required String title,
  required String categoryDb,
  String? bggId,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return null;

  final rows = await CollectionItemScope.ownedByUser(
    client
        .from('collection_items')
        .select(
          'id, quantity, title, bgg_id:metadata->>bgg_id, '
          'original_title:metadata->>original_title',
        )
        .eq('category', categoryDb)
        .eq('is_wishlist', false),
    userId: userId,
  ).limit(1000);
  final list = (rows as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  return matchCatalogDuplicate(list, title: title, bggId: bggId);
}

/// Premier doublon par `bgg_id`, sinon par titre (affiché ou d'origine).
Map<String, dynamic>? matchCatalogDuplicate(
  List<Map<String, dynamic>> rows, {
  required String title,
  String? bggId,
}) {
  final id = bggId?.trim();
  if (id != null && id.isNotEmpty) {
    for (final row in rows) {
      final meta = row['metadata'];
      final rowId = (row['bgg_id'] ??
              (meta is Map ? meta['bgg_id'] : null))
          ?.toString()
          .trim();
      if (rowId == id) return row;
    }
  }
  final t = title.trim().toLowerCase();
  for (final row in rows) {
    final meta = row['metadata'];
    final names = [
      row['title'],
      row['original_title'] ?? (meta is Map ? meta['original_title'] : null),
    ];
    for (final n in names) {
      if (n != null && n.toString().trim().toLowerCase() == t) return row;
    }
  }
  return null;
}

/// Après un ajout collection : retire le doublon wishlist (même bgg_id / titre).
/// Retourne true si une ligne wishlist a été consommée.
Future<bool> consumeWishlistDuplicateForCollectionAdd({
  required String title,
  required String categoryDb,
  String? bggId,
  String? subcategory,
}) async {
  final dup = await findWishlistDuplicate(
    title: title,
    categoryDb: categoryDb,
    bggId: bggId,
    subcategory: subcategory,
  );
  if (dup == null) return false;
  final id = dup['id']?.toString();
  if (id == null || id.isEmpty) return false;
  try {
    await Supabase.instance.client
        .from('collection_items')
        .delete()
        .eq('id', id)
        .eq('is_wishlist', true);
    CollectionRefresh.instance.bump();
    return true;
  } catch (_) {
    return false;
  }
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
