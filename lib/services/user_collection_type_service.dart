import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/user_collection_type.dart';
import 'supabase_read_cache.dart';

class UserCollectionTypeService {
  final _client = Supabase.instance.client;

  Future<List<UserCollectionType>> fetchMine({bool force = false}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    return SupabaseReadCache.getOrFetch<List<UserCollectionType>>(
      key: 'user_collection_types:$userId',
      force: force,
      loader: () async {
        final rows = await _client
            .from('user_collection_types')
            .select()
            .eq('owner_id', userId)
            .order('name');
        return (rows as List)
            .map((r) => UserCollectionType.fromJson(r as Map<String, dynamic>))
            .toList();
      },
    );
  }

  Future<UserCollectionType?> create(UserCollectionType type) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('user_collection_types')
        .insert(type.toInsertJson(userId))
        .select()
        .single();
    SupabaseReadCache.invalidate('user_collection_types:');
    return UserCollectionType.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('user_collection_types').delete().eq('id', id);
    SupabaseReadCache.invalidate('user_collection_types:');
  }

  /// Supprime le type et tous les objets `custom` associés.
  Future<void> deleteWithCleanup(String id) async {
    await _client
        .from('collection_items')
        .delete()
        .eq('category', CollectionCategory.custom.dbValue)
        .eq('subcategory', id);
    await delete(id);
  }
}
