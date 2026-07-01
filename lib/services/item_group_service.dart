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

  Future<Map<String, Set<String>>> fetchMembershipMap(
    List<String> itemIds,
  ) async {
    if (itemIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('collection_item_groups')
          .select('item_id, group_id')
          .inFilter('item_id', itemIds);
      final map = <String, Set<String>>{};
      for (final row in rows as List) {
        final itemId = row['item_id'] as String;
        map.putIfAbsent(itemId, () => {}).add(row['group_id'] as String);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Applique ajouts/retraits de groupes en lot (une passe DB + mises à jour parallèles).
  Future<void> bulkApplyGroupMembershipChanges({
    required List<CollectionItem> items,
    required Set<String> addGroupIds,
    required Set<String> removeGroupIds,
  }) async {
    if (items.isEmpty) return;
    if (addGroupIds.isEmpty && removeGroupIds.isEmpty) return;

    final itemIds = items.map((i) => i.id).toList();
    final membership = await fetchMembershipMap(itemIds);

    final junctionInserts = <Map<String, String>>[];
    final junctionDeletes = <({String itemId, String groupId})>[];
    final nextByItem = <String, Set<String>>{};

    for (final item in items) {
      final current = Set<String>.from(membership[item.id] ?? const {});
      final next = Set<String>.from(current);
      for (final gid in addGroupIds) {
        if (next.add(gid) && !current.contains(gid)) {
          junctionInserts.add({'item_id': item.id, 'group_id': gid});
        }
      }
      for (final gid in removeGroupIds) {
        if (current.contains(gid) && next.remove(gid)) {
          junctionDeletes.add((itemId: item.id, groupId: gid));
        }
      }
      if (next.length != current.length ||
          !next.containsAll(current) ||
          !current.containsAll(next)) {
        nextByItem[item.id] = next;
      }
    }

    if (junctionDeletes.isNotEmpty) {
      await Future.wait(
        junctionDeletes.map(
          (row) => _client
              .from('collection_item_groups')
              .delete()
              .eq('item_id', row.itemId)
              .eq('group_id', row.groupId),
        ),
      );
    }

    if (junctionInserts.isNotEmpty) {
      await _client.from('collection_item_groups').upsert(
            junctionInserts,
            onConflict: 'item_id,group_id',
          );
    }

    if (nextByItem.isEmpty) return;

    final itemsById = {for (final i in items) i.id: i};
    await Future.wait(
      nextByItem.entries.map(
        (e) => _updateItemRowAfterGroups(itemsById[e.key]!, e.value.toList()),
      ),
    );
  }

  Future<void> _updateItemRowAfterGroups(
    CollectionItem item,
    List<String> groupIds,
  ) async {
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

  /// Ajoute plusieurs objets à un groupe (wishlist ou collection).
  Future<void> bulkAddItemsToGroup({
    required String groupId,
    required List<CollectionItem> items,
  }) async {
    await bulkApplyGroupMembershipChanges(
      items: items,
      addGroupIds: {groupId},
      removeGroupIds: const {},
    );
  }

  /// Ajoute plusieurs objets à plusieurs groupes.
  Future<void> bulkAddItemsToGroups({
    required List<String> groupIds,
    required List<CollectionItem> items,
  }) async {
    await bulkApplyGroupMembershipChanges(
      items: items,
      addGroupIds: groupIds.toSet(),
      removeGroupIds: const {},
    );
  }

  /// Retire plusieurs objets d'un groupe.
  Future<void> bulkRemoveItemsFromGroup({
    required String groupId,
    required List<CollectionItem> items,
  }) async {
    await bulkApplyGroupMembershipChanges(
      items: items,
      addGroupIds: const {},
      removeGroupIds: {groupId},
    );
  }

  /// Retire plusieurs objets de plusieurs groupes.
  Future<void> bulkRemoveItemsFromGroups({
    required List<String> groupIds,
    required List<CollectionItem> items,
  }) async {
    await bulkApplyGroupMembershipChanges(
      items: items,
      addGroupIds: const {},
      removeGroupIds: groupIds.toSet(),
    );
  }

  /// Groupes auxquels au moins un des objets appartient.
  Future<Set<String>> groupIdsForItems(Iterable<CollectionItem> items) async {
    final map = await fetchMembershipMap(items.map((i) => i.id).toList());
    return map.values.expand((s) => s).toSet();
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
