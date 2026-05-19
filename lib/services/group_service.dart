import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';

class GroupService {
  final _client = Supabase.instance.client;
  final _picker = ImagePicker();

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<CollectionGroup>> fetchMyGroups() async {
    final userId = _userId;
    if (userId == null) return [];

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

  Future<CollectionGroup> fetchGroup(String groupId) async {
    final row =
        await _client.from('groups').select().eq('id', groupId).single();
    return CollectionGroup.fromJson(Map<String, dynamic>.from(row));
  }

  bool canEdit(CollectionGroup group) => group.createdBy == _userId;

  Future<CollectionGroup> createGroup(String name) async {
    final userId = _userId!;
    final row = await _client
        .from('groups')
        .insert({
          'name': name.trim(),
          'created_by': userId,
          'icon_key': 'groups',
          'accent_color': '#673AB7',
        })
        .select()
        .single();
    final group = CollectionGroup.fromJson(Map<String, dynamic>.from(row));
    await _client.from('group_members').insert({
      'group_id': group.id,
      'profile_id': userId,
    });
    return group;
  }

  Future<CollectionGroup> updateGroup(CollectionGroup group) async {
    if (!canEdit(group)) {
      throw Exception('Seul le créateur du groupe peut le modifier');
    }

    final row = await _client
        .from('groups')
        .update(group.toUpdateJson())
        .eq('id', group.id)
        .select()
        .single();

    return CollectionGroup.fromJson(Map<String, dynamic>.from(row));
  }

  Future<String> pickAndUploadGroupAvatar(String groupId) async {
    if (_userId == null) throw Exception('Non connecté');

    final group = await fetchGroup(groupId);
    if (!canEdit(group)) {
      throw Exception('Seul le créateur peut changer la photo');
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) throw Exception('Aucune image sélectionnée');

    return uploadGroupAvatarBytes(groupId, await picked.readAsBytes());
  }

  Future<String> uploadGroupAvatarBytes(String groupId, Uint8List bytes) async {
    final group = await fetchGroup(groupId);
    if (!canEdit(group)) {
      throw Exception('Seul le créateur peut changer la photo');
    }

    final path = '$groupId/avatar.jpg';
    await _client.storage.from('group-avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    final publicUrl =
        _client.storage.from('group-avatars').getPublicUrl(path);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> removeGroupAvatar(String groupId) async {
    final group = await fetchGroup(groupId);
    if (!canEdit(group)) {
      throw Exception('Seul le créateur peut supprimer la photo');
    }

    try {
      await _client.storage.from('group-avatars').remove(['$groupId/avatar.jpg']);
    } catch (_) {}

    await _client
        .from('groups')
        .update({'avatar_url': null})
        .eq('id', groupId);
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
        .select(
          'profile_id, profiles(username, avatar_url, accent_color)',
        )
        .eq('group_id', groupId);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Supprime le groupe (cascade membres ; objets : group_id → null en base).
  Future<void> deleteGroup(String groupId) async {
    final group = await fetchGroup(groupId);
    if (!canEdit(group)) {
      throw Exception('Seul le créateur peut supprimer ce groupe');
    }
    await _client.from('groups').delete().eq('id', groupId);
  }
}
