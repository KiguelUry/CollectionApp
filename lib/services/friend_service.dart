import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/collection_item_filters.dart';
import '../utils/friend_item_overlap.dart';
import '../utils/supabase_embeds.dart';
import '../utils/search_relevance.dart';
import 'supabase_read_cache.dart';

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

  void invalidateFriendCache() {
    _cachedFriendIds = null;
    SupabaseReadCache.invalidate('friendships:');
    SupabaseReadCache.invalidate('profile_privacy:');
  }

  Future<List<String>> listFriendProfileIds() async {
    return (await _myFriendIds()).toList();
  }

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

  Future<void> removeFriend(String friendshipId) async {
    await _client.from('friendships').delete().eq('id', friendshipId);
    invalidateFriendCache();
  }

  Future<List<Map<String, dynamic>>> fetchFriends({bool force = false}) async {
    final userId = _client.auth.currentUser!.id;
    return SupabaseReadCache.getOrFetch<List<Map<String, dynamic>>>(
      key: 'friendships:list:$userId',
      force: force,
      loader: () async {
        final rows = await _client
            .from('friendships')
            .select('id, share_collections, requester_id, addressee_id')
            .eq('status', 'accepted')
            .or('requester_id.eq.$userId,addressee_id.eq.$userId');

        final list = rows as List;
        if (list.isEmpty) return <Map<String, dynamic>>[];

        final otherIds = list
            .map(
              (row) => row['requester_id'] == userId
                  ? row['addressee_id'] as String
                  : row['requester_id'] as String,
            )
            .toList();

        final profiles = await _client
            .from('profiles')
            .select('id, username, avatar_url, accent_color, greeting_grammar')
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
                'greeting_grammar': p?['greeting_grammar'],
                'share_collections': row['share_collections'],
              };
            }(),
        ];
      },
    );
  }

  Future<void> setShareCollections(String friendshipId, bool share) async {
    await _client
        .from('friendships')
        .update({'share_collections': share})
        .eq('id', friendshipId);
    invalidateFriendCache();
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

    return SupabaseReadCache.getOrFetch<Map<String, dynamic>?>(
      key: 'friendships:with:$userId:$friendProfileId',
      loader: () async {
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
      },
    );
  }

  Future<bool> canViewFriendCollection(String friendProfileId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId != null && userId == friendProfileId) return true;

    final friendship = await friendshipWith(friendProfileId);
    if (friendship == null) return false;
    if (friendship['share_collections'] != true) return false;

    final hide = await SupabaseReadCache.getOrFetch<bool>(
      key: 'profile_privacy:hide_friends:$friendProfileId',
      loader: () async {
        final profile = await _client
            .from('profiles')
            .select('hide_collection_from_friends')
            .eq('id', friendProfileId)
            .maybeSingle();
        return profile?['hide_collection_from_friends'] == true;
      },
    );
    return !hide;
  }

  /// Un objet précis chez un ami (fil d'activité, lien direct).
  Future<CollectionItem?> fetchFriendItem(
    String friendProfileId,
    String itemId,
  ) async {
    if (!await canViewFriendCollection(friendProfileId)) return null;

    final row = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItem)
        .eq('id', itemId)
        .maybeSingle();
    if (row == null) return null;
    return CollectionItem.fromJson(Map<String, dynamic>.from(row));
  }

  /// Collection active de l'ami (perso + groupes visibles via RLS).
  Future<List<CollectionItem>> fetchFriendRecentBoardgames(
    String friendProfileId, {
    int limit = 20,
  }) {
    return fetchFriendRecentByCategory(
      friendProfileId,
      CollectionCategory.boardgame,
      limit: limit,
    );
  }

  Future<List<CollectionItem>> fetchFriendRecentByCategory(
    String friendProfileId,
    CollectionCategory category, {
    int limit = 20,
  }) async {
    if (!await canViewFriendCollection(friendProfileId)) {
      return [];
    }
    final common = await commonGroupIds(friendProfileId);

    final rows = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItem)
        .eq('added_by', friendProfileId)
        .eq('category', category.dbValue)
        .eq('is_wishlist', false)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .where(isActiveCollectionItem)
        .where((i) => isFriendOwnedVisible(i, friendProfileId, common))
        .toList();
  }

  /// Un objet appartient à la collection d'un ami s'il l'a ajouté lui-même,
  /// en perso ou dans un groupe où vous êtes **tous les deux** membres.
  /// `location_user_id` (objet physiquement chez lui) ne compte pas :
  /// c'est souvent un objet d'un autre membre posé chez lui.
  static bool isFriendOwnedVisible(
    CollectionItem item,
    String friendProfileId,
    Set<String> commonGroupIds,
  ) {
    if (item.addedBy != friendProfileId) return false;
    final gid = item.groupId;
    return gid == null || gid.isEmpty || commonGroupIds.contains(gid);
  }

  /// Groupes dont toi ET cet ami êtes membres.
  Future<Set<String>> commonGroupIds(String friendProfileId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};
    final ids = await SupabaseReadCache.getOrFetch<List<String>>(
      key: 'group_members:common:$userId:$friendProfileId',
      loader: () async {
        try {
          final rows = await _client
              .from('group_members')
              .select('group_id, profile_id')
              .inFilter('profile_id', [userId, friendProfileId]);
          final mine = <String>{};
          final theirs = <String>{};
          for (final r in rows as List) {
            final gid = r['group_id']?.toString();
            if (gid == null) continue;
            if (r['profile_id'] == userId) mine.add(gid);
            if (r['profile_id'] == friendProfileId) theirs.add(gid);
          }
          return mine.intersection(theirs).toList();
        } catch (_) {
          return <String>[];
        }
      },
    );
    return ids.toSet();
  }

  Future<List<CollectionItem>> fetchFriendCollectionItems(
    String friendProfileId,
  ) async {
    if (!await canViewFriendCollection(friendProfileId)) {
      throw Exception(
        'Collection non partagée (active le partage mutuel ou demande à ton ami)',
      );
    }
    final common = await commonGroupIds(friendProfileId);

    final rows = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItem)
        .eq('added_by', friendProfileId)
        .eq('is_wishlist', false)
        .order('title');

    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .where(isActiveCollectionItem)
        .where((i) => isFriendOwnedVisible(i, friendProfileId, common))
        .toList();
  }

  /// Objets des groupes **communs** avec cet ami (ajoutés par n'importe quel
  /// membre). Vide si vous n'avez aucun groupe en commun.
  Future<List<CollectionItem>> fetchItemsInCommonGroups(
    String friendProfileId,
  ) async {
    final ids = (await commonGroupIds(friendProfileId)).toList();
    if (ids.isEmpty) return [];

    final rows = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItem)
        .inFilter('group_id', ids)
        .eq('is_wishlist', false);

    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .where(isActiveCollectionItem)
        .toList();
  }

  /// Demandes d'ami que j'ai envoyées (en attente).
  Future<List<Map<String, dynamic>>> fetchOutgoingFriendRequests() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('friendships')
        .select('id, addressee_id, created_at')
        .eq('requester_id', userId)
        .eq('status', 'pending')
        .order('created_at');
    final list = rows as List;
    if (list.isEmpty) return [];
    final ids = list.map((r) => r['addressee_id'] as String).toList();
    List profiles = const [];
    try {
      profiles = await _client
          .from('profiles')
          .select('id, username, avatar_url, accent_color')
          .inFilter('id', ids) as List;
    } catch (_) {}
    final byId = {
      for (final p in profiles) p['id'] as String: Map<String, dynamic>.from(p),
    };
    return [
      for (final row in list)
        {
          'friendship_id': row['id'],
          'profile_id': row['addressee_id'],
          'username': 'Utilisateur',
          ...?byId[row['addressee_id'] as String],
        },
    ];
  }

  /// Annule une demande envoyée (encore en attente).
  Future<void> cancelFriendRequest(String friendshipId) async {
    final userId = _client.auth.currentUser!.id;
    await _client
        .from('friendships')
        .delete()
        .eq('id', friendshipId)
        .eq('requester_id', userId)
        .eq('status', 'pending');
    invalidateFriendCache();
  }

  /// Nombre d'objets possédés par ami + nombre en commun avec moi.
  /// Une seule requête légère (titre, catégorie, bgg_id — pas de metadata).
  Future<Map<String, ({int count, int common})>> fetchFriendsSummary(
    List<String> friendIds,
  ) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || friendIds.isEmpty) return {};
    final sorted = [...friendIds]..sort();
    return SupabaseReadCache.getOrFetch<Map<String, ({int count, int common})>>(
      key: 'friends:summary:$userId:${sorted.join(',')}',
      loader: () async {
        try {
          final rows = await _client
              .from('collection_items')
              .select(
                'added_by, title, category, is_expansion, '
                'bgg_id:metadata->>bgg_id, original_title:metadata->>original_title',
              )
              .inFilter('added_by', sorted)
              .eq('is_wishlist', false)
              .filter('group_id', 'is', null);
          final byFriend = <String, List<Map<String, dynamic>>>{};
          for (final r in rows as List) {
            final m = Map<String, dynamic>.from(r as Map);
            if (m['is_expansion'] == true) continue;
            byFriend.putIfAbsent(m['added_by'] as String, () => []).add(m);
          }
          final mine = await myOverlapItems();
          final myKeys = overlapKeysForRows([
            for (final i in mine)
              if (!i.isWishlist) overlapRowOf(i),
          ]);
          return {
            for (final id in sorted)
              id: (
                count: byFriend[id]?.length ?? 0,
                common: (byFriend[id] ?? const [])
                    .where((r) => overlapKeysForRow(r).any(myKeys.contains))
                    .length,
              ),
          };
        } catch (_) {
          return <String, ({int count, int common})>{};
        }
      },
    );
  }

  Future<bool> canViewFriendWishlist(String friendProfileId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId != null && userId == friendProfileId) return true;
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

    final common = await commonGroupIds(friendProfileId);
    final rows = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItem)
        .eq('added_by', friendProfileId)
        .eq('is_wishlist', true)
        .order('title');

    return dedupeCatalogItems(
      (rows as List)
          .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
          .where((i) => isFriendOwnedVisible(i, friendProfileId, common))
          .toList(),
    );
  }
}
