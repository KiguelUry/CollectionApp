import 'package:supabase_flutter/supabase_flutter.dart';

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
