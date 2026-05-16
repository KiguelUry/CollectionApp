import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_group.dart';

class GroupService {
  final _client = Supabase.instance.client;

  Future<List<CollectionGroup>> fetchMyGroups() async {
    final userId = _client.auth.currentUser!.id;
    final memberRows = await _client
        .from('group_members')
        .select('group_id')
        .eq('profile_id', userId);
    final ids = (memberRows as List)
        .map((r) => r['group_id'] as String)
        .toList();
    if (ids.isEmpty) return [];

    final groups = await _client
        .from('groups')
        .select()
        .inFilter('id', ids)
        .order('name');
    return (groups as List)
        .map((g) => CollectionGroup.fromJson(Map<String, dynamic>.from(g)))
        .toList();
  }

  Future<CollectionGroup> createGroup(String name) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('groups')
        .insert({'name': name.trim(), 'created_by': userId})
        .select()
        .single();
    final group = CollectionGroup.fromJson(Map<String, dynamic>.from(row));
    await _client.from('group_members').insert({
      'group_id': group.id,
      'profile_id': userId,
    });
    return group;
  }

  Future<void> addMember(String groupId, String profileId) async {
    await _client.from('group_members').insert({
      'group_id': groupId,
      'profile_id': profileId,
    });
  }

  Future<List<Map<String, dynamic>>> fetchMembers(String groupId) async {
    final rows = await _client
        .from('group_members')
        .select('profile_id, profiles(username)')
        .eq('group_id', groupId);
    return List<Map<String, dynamic>>.from(rows);
  }
}
