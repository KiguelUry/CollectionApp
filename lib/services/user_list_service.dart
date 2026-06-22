import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../models/user_list.dart';
import 'profile_service.dart';

class UserListService {
  final _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  Future<List<UserList>> fetchMine() async {
    final rows = await _client
        .from('user_lists')
        .select()
        .eq('owner_id', _userId)
        .order('updated_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows)
        .map(UserList.fromJson)
        .toList();
  }

  Future<UserList?> fetchById(String id) async {
    final row = await _client
        .from('user_lists')
        .select()
        .eq('id', id)
        .eq('owner_id', _userId)
        .maybeSingle();
    if (row == null) return null;
    return UserList.fromJson(row);
  }

  Future<UserListWithItems> fetchWithItems(String listId) async {
    final list = await fetchById(listId);
    if (list == null) throw StateError('Liste introuvable');

    final linkRows = await _client
        .from('user_list_items')
        .select('item_id, sort_index')
        .eq('list_id', listId)
        .order('sort_index');

    final links = List<Map<String, dynamic>>.from(linkRows);
    if (links.isEmpty) {
      return UserListWithItems(list: list, items: const []);
    }

    final ids = links.map((r) => r['item_id'] as String).toList();
    final itemRows = await _client
        .from('collection_items')
        .select()
        .inFilter('id', ids);

    final byId = {
      for (final row in List<Map<String, dynamic>>.from(itemRows))
        row['id'] as String: CollectionItem.fromJson(row),
    };

    final items = <CollectionItem>[];
    for (final link in links) {
      final item = byId[link['item_id'] as String];
      if (item != null) items.add(item);
    }

    return UserListWithItems(list: list, items: items);
  }

  Future<List<UserListWithItems>> fetchAllWithPreviewItems() async {
    final lists = await fetchMine();
    final out = <UserListWithItems>[];
    for (final list in lists) {
      out.add(await fetchWithItems(list.id));
    }
    return out;
  }

  Future<UserList> create({
    required String name,
    String? description,
    String colorHex = '#00A896',
  }) async {
    await ProfileService().ensureCurrentUserProfile();
    final row = await _client
        .from('user_lists')
        .insert({
          'owner_id': _userId,
          'name': name.trim(),
          'description': description?.trim(),
          'color_hex': colorHex,
        })
        .select()
        .single();
    return UserList.fromJson(row);
  }

  Future<void> update(UserList list) async {
    await _client
        .from('user_lists')
        .update(list.toUpdateJson())
        .eq('id', list.id)
        .eq('owner_id', _userId);
  }

  Future<void> delete(String listId) async {
    await _client
        .from('user_lists')
        .delete()
        .eq('id', listId)
        .eq('owner_id', _userId);
  }

  Future<void> addItem(String listId, String itemId) async {
    final existing = await _client
        .from('user_list_items')
        .select('sort_index')
        .eq('list_id', listId)
        .order('sort_index', ascending: false)
        .limit(1)
        .maybeSingle();

    final nextIndex = existing == null
        ? 0
        : ((existing['sort_index'] as int?) ?? 0) + 1;

    await _client.from('user_list_items').upsert({
      'list_id': listId,
      'item_id': itemId,
      'sort_index': nextIndex,
    });

    await _touchList(listId);
    await _maybeRefreshCover(listId);
  }

  Future<void> removeItem(String listId, String itemId) async {
    await _client
        .from('user_list_items')
        .delete()
        .eq('list_id', listId)
        .eq('item_id', itemId);
    await _touchList(listId);
    await _maybeRefreshCover(listId);
  }

  Future<void> _touchList(String listId) async {
    await _client.from('user_lists').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', listId);
  }

  Future<void> _maybeRefreshCover(String listId) async {
    final bundle = await fetchWithItems(listId);
    final cover = bundle.previewCoverUrls.isNotEmpty
        ? bundle.previewCoverUrls.first
        : null;
    if (cover != bundle.list.coverUrl) {
      await update(bundle.list.copyWith(coverUrl: cover));
    }
  }

  Future<List<CollectionItem>> fetchAddableItems(String listId) async {
    final bundle = await fetchWithItems(listId);
    final existing = bundle.items.map((i) => i.id).toSet();

    final rows = await _client.from('collection_items').select();
    return List<Map<String, dynamic>>.from(rows)
        .map(CollectionItem.fromJson)
        .where((i) =>
            !i.isSold &&
            !existing.contains(i.id) &&
            (i.addedBy == _userId || i.locationUserId == _userId))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
}
