import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_collection_type.dart';

class UserCollectionTypeService {
  final _client = Supabase.instance.client;

  Future<List<UserCollectionType>> fetchMine() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await _client
        .from('user_collection_types')
        .select()
        .eq('owner_id', userId)
        .order('name');

    return (rows as List)
        .map((r) => UserCollectionType.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<UserCollectionType?> create(UserCollectionType type) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('user_collection_types')
        .insert(type.toInsertJson(userId))
        .select()
        .single();

    return UserCollectionType.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('user_collection_types').delete().eq('id', id);
  }
}
