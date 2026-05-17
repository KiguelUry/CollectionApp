import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/search_relevance.dart';

class FriendService {
  final _client = Supabase.instance.client;

  Set<String>? _cachedFriendIds;

  Future<Set<String>> _myFriendIds() async {
    if (_cachedFriendIds != null) return _cachedFriendIds!;

    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('friendships')
        .select('requester_id, addressee_id')
        .eq('status', 'accepted')
        .or('requester_id.eq.$userId,addressee_id.eq.$userId');

    final ids = <String>{};
    for (final row in rows as List) {
      ids.add(
        row['requester_id'] == userId
            ? row['addressee_id'] as String
            : row['requester_id'] as String,
      );
    }
    _cachedFriendIds = ids;
    return ids;
  }

  void invalidateFriendCache() => _cachedFriendIds = null;

  /// Recherche de profils : pertinence pseudo, amis en commun, pas déjà amis.
  Future<List<Map<String, dynamic>>> searchProfiles(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 1) return [];

    final userId = _client.auth.currentUser!.id;
    final friendIds = await _myFriendIds();

    final rows = await _client
        .from('profiles')
        .select('id, username, avatar_url, accent_color')
        .ilike('username', '%$trimmed%')
        .neq('id', userId)
        .limit(30);

    final candidates = List<Map<String, dynamic>>.from(rows);
    if (candidates.isEmpty) return [];

    final candidateIds = candidates.map((c) => c['id'] as String).toList();
    final mutualCounts = await _mutualFriendCounts(
      candidateIds: candidateIds,
      myFriendIds: friendIds,
    );

    final scored = <Map<String, dynamic>>[];
    for (final p in candidates) {
      final id = p['id'] as String;
      if (friendIds.contains(id)) continue;

      final username = p['username'] as String;
      final mutual = mutualCounts[id] ?? 0;
      var score = titleRelevanceScore(username, trimmed);
      if (mutual > 0) score += 80 + (mutual * 25);

      scored.add({
        ...p,
        '_score': score,
        if (mutual > 0) 'mutual_friends': mutual,
      });
    }

    sortByScore(scored, (p) => p['_score'] as int);
    return scored.take(12).map((p) {
      final copy = Map<String, dynamic>.from(p);
      copy.remove('_score');
      return copy;
    }).toList();
  }

  Future<Map<String, int>> _mutualFriendCounts({
    required List<String> candidateIds,
    required Set<String> myFriendIds,
  }) async {
    if (candidateIds.isEmpty || myFriendIds.isEmpty) {
      return {for (final id in candidateIds) id: 0};
    }

    final idsFilter = candidateIds.join(',');
    final rows = await _client
        .from('friendships')
        .select('requester_id, addressee_id')
        .eq('status', 'accepted')
        .or(
          'requester_id.in.($idsFilter),addressee_id.in.($idsFilter)',
        );

    final counts = {for (final id in candidateIds) id: 0};
    for (final row in rows as List) {
      final r = row['requester_id'] as String;
      final a = row['addressee_id'] as String;

      if (candidateIds.contains(r) && myFriendIds.contains(a)) {
        counts[r] = (counts[r] ?? 0) + 1;
      }
      if (candidateIds.contains(a) && myFriendIds.contains(r)) {
        counts[a] = (counts[a] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<void> addFriendByUsername(String username) async {
    final userId = _client.auth.currentUser!.id;
    final profile = await _client
        .from('profiles')
        .select('id, username, avatar_url, accent_color')
        .eq('username', username.trim())
        .maybeSingle();
    if (profile == null) {
      throw Exception('Aucun profil trouvé pour « $username »');
    }
    final friendId = profile['id'] as String;
    if (friendId == userId) {
      throw Exception('Tu ne peux pas t\'ajouter toi-même');
    }

    final existing = await _client
        .from('friendships')
        .select('id')
        .or(
          'and(requester_id.eq.$userId,addressee_id.eq.$friendId),and(requester_id.eq.$friendId,addressee_id.eq.$userId)',
        )
        .maybeSingle();
    if (existing != null) {
      throw Exception('Cet utilisateur est déjà dans tes amis');
    }

    await _client.from('friendships').insert({
      'requester_id': userId,
      'addressee_id': friendId,
      'status': 'accepted',
      'share_collections': true,
    });
    invalidateFriendCache();
  }

  Future<List<Map<String, dynamic>>> fetchFriends() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('friendships')
        .select('id, share_collections, requester_id, addressee_id')
        .eq('status', 'accepted')
        .or('requester_id.eq.$userId,addressee_id.eq.$userId');

    final list = rows as List;
    if (list.isEmpty) return [];

    final otherIds = list
        .map(
          (row) => row['requester_id'] == userId
              ? row['addressee_id'] as String
              : row['requester_id'] as String,
        )
        .toList();

    final profiles = await _client
        .from('profiles')
        .select('id, username, avatar_url, accent_color')
        .inFilter('id', otherIds);

    final byId = {
      for (final p in profiles as List)
        p['id'] as String: Map<String, dynamic>.from(p),
    };

    return [
      for (final row in list)
        () {
          final pid = row['requester_id'] == userId
              ? row['addressee_id'] as String
              : row['requester_id'] as String;
          final p = byId[pid];
          return {
            'friendship_id': row['id'],
            'profile_id': pid,
            'username': p?['username'] as String? ?? 'Ami',
            'avatar_url': p?['avatar_url'],
            'accent_color': p?['accent_color'],
            'share_collections': row['share_collections'],
          };
        }(),
    ];
  }

  Future<void> setShareCollections(String friendshipId, bool share) async {
    await _client
        .from('friendships')
        .update({'share_collections': share})
        .eq('id', friendshipId);
  }
}
