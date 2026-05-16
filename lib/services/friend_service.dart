import 'package:supabase_flutter/supabase_flutter.dart';

class FriendService {
  final _client = Supabase.instance.client;

  Future<void> addFriendByUsername(String username) async {
    final userId = _client.auth.currentUser!.id;
    final profile = await _client
        .from('profiles')
        .select('id, username')
        .eq('username', username.trim())
        .maybeSingle();
    if (profile == null) {
      throw Exception('Aucun profil trouvé pour « $username »');
    }
    final friendId = profile['id'] as String;
    if (friendId == userId) {
      throw Exception('Tu ne peux pas t\'ajouter toi-même');
    }

    await _client.from('friendships').insert({
      'requester_id': userId,
      'addressee_id': friendId,
      'status': 'accepted',
      'share_collections': true,
    });
  }

  Future<List<Map<String, dynamic>>> fetchFriends() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('friendships')
        .select('id, share_collections, requester_id, addressee_id')
        .eq('status', 'accepted')
        .or('requester_id.eq.$userId,addressee_id.eq.$userId');

    final friends = <Map<String, dynamic>>[];
    for (final row in rows as List) {
      final otherId = row['requester_id'] == userId
          ? row['addressee_id']
          : row['requester_id'];
      final profile = await _client
          .from('profiles')
          .select('username')
          .eq('id', otherId)
          .single();
      friends.add({
        'friendship_id': row['id'],
        'profile_id': otherId,
        'username': profile['username'],
        'share_collections': row['share_collections'],
      });
    }
    return friends;
  }

  Future<void> setShareCollections(String friendshipId, bool share) async {
    await _client
        .from('friendships')
        .update({'share_collections': share})
        .eq('id', friendshipId);
  }
}
