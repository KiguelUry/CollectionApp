import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/whereabouts_persistence.dart';

/// Synchronise l'appartenance multi-groupe d'un objet.
class ItemGroupService {
  final _client = Supabase.instance.client;

  /// Sync incrémentale (évite les doublons PK sur insert concurrent).
  Future<void> syncItemGroups(String itemId, List<String> groupIds) async {
    final unique = groupIds.toSet();
    final existing = (await fetchGroupIdsForItem(itemId)).toSet();

    final toRemove = existing.difference(unique);
    final toAdd = unique.difference(existing);

    for (final gid in toRemove) {
      await _client
          .from('collection_item_groups')
          .delete()
          .eq('item_id', itemId)
          .eq('group_id', gid);
    }

    if (toAdd.isEmpty) return;

    await _client.from('collection_item_groups').upsert(
          toAdd
              .map(
                (gid) => {
                  'item_id': itemId,
                  'group_id': gid,
                },
              )
              .toList(),
          onConflict: 'item_id,group_id',
        );
  }

  /// Sync groupes + mise à jour de la ligne principale en préservant `holder_label`.
  Future<void> syncItemGroupsWithItem(
    CollectionItem item,
    List<String> groupIds,
  ) async {
    await syncItemGroups(item.id, groupIds);

    final whereabouts = buildWhereaboutsDbFields(item, groupIds: groupIds);
    final whereaboutsMeta = Map<String, dynamic>.from(
      whereabouts['metadata'] as Map<String, dynamic>,
    );

    final row = await _client
        .from('collection_items')
        .select('metadata')
        .eq('id', item.id)
        .maybeSingle();

    var meta = Map<String, dynamic>.from(item.metadata ?? {});
    if (row?['metadata'] is Map) {
      meta = Map<String, dynamic>.from(row!['metadata'] as Map);
    }
    meta = mergeMetadataPreservingHolder(meta, whereaboutsMeta);
    meta = finalizeMetadataPayload(item, meta);

    await _client.from('collection_items').update({
      'group_id': groupIds.isEmpty ? null : groupIds.first,
      'location_user_id': whereabouts['location_user_id'],
      'metadata': meta,
    }).eq('id', item.id);
  }

  Future<List<String>> fetchGroupIdsForItem(String itemId) async {
    try {
      final rows = await _client
          .from('collection_item_groups')
          .select('group_id')
          .eq('item_id', itemId);
      return (rows as List).map((r) => r['group_id'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  /// Ajoute plusieurs objets à un groupe (wishlist ou collection).
  Future<void> bulkAddItemsToGroup({
    required String groupId,
    required List<CollectionItem> items,
  }) async {
    for (final item in items) {
      final ids = await fetchGroupIdsForItem(item.id);
      if (ids.contains(groupId)) continue;
      await syncItemGroupsWithItem(item, [...ids, groupId]);
    }
  }

  /// Ajoute plusieurs objets à plusieurs groupes.
  Future<void> bulkAddItemsToGroups({
    required List<String> groupIds,
    required List<CollectionItem> items,
  }) async {
    final unique = groupIds.toSet();
    for (final groupId in unique) {
      await bulkAddItemsToGroup(groupId: groupId, items: items);
    }
  }

  Future<Set<String>> fetchItemIdsForGroup(String groupId) async {
    try {
      final rows = await _client
          .from('collection_item_groups')
          .select('item_id')
          .eq('group_id', groupId);
      return (rows as List).map((r) => r['item_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }
}
