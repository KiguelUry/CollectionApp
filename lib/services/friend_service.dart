import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/collection_item_filters.dart';
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
    if (trimmed.isEmpty) return [];

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
        .select('id, status')
        .or(
          'and(requester_id.eq.$userId,addressee_id.eq.$friendId),and(requester_id.eq.$friendId,addressee_id.eq.$userId)',
        )
        .maybeSingle();
    if (existing != null) {
      final st = existing['status'] as String?;
      if (st == 'accepted') {
        throw Exception('Cet utilisateur est déjà dans tes amis');
      }
      if (st == 'pending') {
        throw Exception('Une demande d\'amitié est déjà en attente');
      }
      throw Exception('Impossible d\'ajouter cet utilisateur');
    }

    await _client.from('friendships').insert({
      'requester_id': userId,
      'addressee_id': friendId,
      'status': 'pending',
      'share_collections': true,
    });
    invalidateFriendCache();
  }

  Future<List<Map<String, dynamic>>> fetchIncomingFriendRequests() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('friendships')
        .select('id, requester_id, created_at')
        .eq('addressee_id', userId)
        .eq('status', 'pending')
        .order('created_at');

    final list = rows as List;
    if (list.isEmpty) return [];

    final ids = list.map((r) => r['requester_id'] as String).toList();
    final profiles = await _client
        .from('profiles')
        .select('id, username, avatar_url, accent_color')
        .inFilter('id', ids);
    final byId = {
      for (final p in profiles as List)
        p['id'] as String: Map<String, dynamic>.from(p),
    };

    return [
      for (final row in list)
        {
          'friendship_id': row['id'],
          'profile_id': row['requester_id'],
          ...?byId[row['requester_id'] as String],
        },
    ];
  }

  Future<void> acceptFriendRequest(String friendshipId) async {
    await _client
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('id', friendshipId);
    invalidateFriendCache();
  }

  Future<void> rejectFriendRequest(String friendshipId) async {
    await _client.from('friendships').delete().eq('id', friendshipId);
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

  /// Filtre local des amis déjà ajoutés (par pseudo).
  List<Map<String, dynamic>> filterFriends(
    List<Map<String, dynamic>> friends,
    String query,
  ) {
    final q = query.trim();
    if (q.isEmpty) return friends;

    final scored = <Map<String, dynamic>>[];
    for (final f in friends) {
      final username = f['username'] as String? ?? '';
      final score = titleRelevanceScore(username, q);
      if (score > 0) {
        scored.add({...f, '_score': score});
      }
    }

    sortByScore(scored, (f) => f['_score'] as int);
    return scored.map((f) {
      final copy = Map<String, dynamic>.from(f);
      copy.remove('_score');
      return copy;
    }).toList();
  }

  /// Vérifie l'amitié et si les collections sont partagées (flag mutuel).
  Future<Map<String, dynamic>?> friendshipWith(String friendProfileId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('friendships')
        .select('id, share_collections, requester_id, addressee_id')
        .eq('status', 'accepted')
        .or(
          'and(requester_id.eq.$userId,addressee_id.eq.$friendProfileId),'
          'and(requester_id.eq.$friendProfileId,addressee_id.eq.$userId)',
        )
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<bool> canViewFriendCollection(String friendProfileId) async {
    final friendship = await friendshipWith(friendProfileId);
    return friendship != null;
  }

  /// Collection active de l'ami (perso + groupes visibles via RLS).
  Future<List<CollectionItem>> fetchFriendCollectionItems(
    String friendProfileId,
  ) async {
    if (!await canViewFriendCollection(friendProfileId)) {
      throw Exception('Tu dois être ami avec cette personne');
    }

    final rows = await _client
        .from('collection_items')
        .select('*, locations(label), groups(name)')
        .or(
          'added_by.eq.$friendProfileId,location_user_id.eq.$friendProfileId',
        )
        .eq('is_wishlist', false)
        .order('title');

    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .where(isActiveCollectionItem)
        .toList();
  }

  Future<bool> canViewFriendWishlist(String friendProfileId) async {
    if (!await canViewFriendCollection(friendProfileId)) return false;

    final row = await _client
        .from('profiles')
        .select('share_wishlist')
        .eq('id', friendProfileId)
        .maybeSingle();
    return row?['share_wishlist'] as bool? ?? true;
  }

  /// Wishlist de l'ami (si partage activé sur son profil).
  Future<List<CollectionItem>> fetchFriendWishlistItems(
    String friendProfileId,
  ) async {
    if (!await canViewFriendWishlist(friendProfileId)) {
      throw Exception('Cette wishlist n\'est pas partagée');
    }

    final rows = await _client
        .from('collection_items')
        .select('*, locations(label), groups(name)')
        .or(
          'added_by.eq.$friendProfileId,location_user_id.eq.$friendProfileId',
        )
        .eq('is_wishlist', true)
        .order('title');

    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }
}
