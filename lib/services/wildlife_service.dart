import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../models/wildlife_taxonomy.dart';
import '../models/wildlife_observation.dart';

class WildlifeMapPoint {
  final WildlifeObservation observation;
  final String speciesTitle;
  final WildlifeRealm realm;

  const WildlifeMapPoint({
    required this.observation,
    required this.speciesTitle,
    required this.realm,
  });
}

class WildlifeRealmStat {
  final WildlifeRealm realm;
  final int observationCount;
  final int speciesCount;

  const WildlifeRealmStat({
    required this.realm,
    required this.observationCount,
    required this.speciesCount,
  });
}

class WildlifeFriendStat {
  final String profileId;
  final String username;
  final String? avatarUrl;
  final int speciesCount;
  final int observationCount;
  final Map<WildlifeRealm, int> speciesByRealm;

  const WildlifeFriendStat({
    required this.profileId,
    required this.username,
    this.avatarUrl,
    required this.speciesCount,
    required this.observationCount,
    required this.speciesByRealm,
  });
}

class WildlifeService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<WildlifeObservation>> fetchForItem(String itemId) async {
    try {
      final rows = await _client
          .from('wildlife_observations')
          .select()
          .eq('item_id', itemId)
          .order('observed_at', ascending: false);
      return (rows as List)
          .map((r) => WildlifeObservation.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<WildlifeObservation>> fetchAllForMap() async {
    final id = _userId;
    if (id == null) return [];
    try {
      final rows = await _client
          .from('wildlife_observations')
          .select()
          .eq('user_id', id)
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);
      return (rows as List)
          .map((r) => WildlifeObservation.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<WildlifeMapPoint>> fetchMapPoints() async {
    final observations = await fetchAllForMap();
    if (observations.isEmpty) return [];

    final itemIds = observations.map((o) => o.itemId).toSet().toList();
    final rows = await _client
        .from('collection_items')
        .select('id, title, metadata')
        .inFilter('id', itemIds);

    final itemsById = <String, CollectionItem>{};
    for (final row in rows as List) {
      final item = CollectionItem.fromJson(Map<String, dynamic>.from(row));
      itemsById[item.id] = item;
    }

    return [
      for (final o in observations)
        if (itemsById.containsKey(o.itemId))
          WildlifeMapPoint(
            observation: o,
            speciesTitle: itemsById[o.itemId]!.title,
            realm: WildlifeRealm.fromDb(
              itemsById[o.itemId]!.metadata?['wildlife_realm'] as String?,
            ),
          ),
    ];
  }

  List<WildlifeRealmStat> realmStatsFromItems(List<CollectionItem> items) {
    final obsPerRealm = <WildlifeRealm, int>{};
    final speciesPerRealm = <WildlifeRealm, Set<String>>{};

    for (final item in items) {
      final realm = WildlifeRealm.fromDb(
        item.metadata?['wildlife_realm'] as String?,
      );
      final obs = item.gamesPlayed ?? 0;
      if (obs > 0) {
        obsPerRealm[realm] = (obsPerRealm[realm] ?? 0) + obs;
        speciesPerRealm.putIfAbsent(realm, () => {}).add(item.id);
      }
    }

    return WildlifeRealm.values
        .map(
          (r) => WildlifeRealmStat(
            realm: r,
            observationCount: obsPerRealm[r] ?? 0,
            speciesCount: speciesPerRealm[r]?.length ?? 0,
          ),
        )
        .where((s) => s.observationCount > 0 || s.speciesCount > 0)
        .toList();
  }

  Future<List<WildlifeFriendStat>> fetchFriendsComparison() async {
    final userId = _userId;
    if (userId == null) return [];

    final friendships = await _client
        .from('friendships')
        .select('requester_id, addressee_id')
        .eq('status', 'accepted')
        .or('requester_id.eq.$userId,addressee_id.eq.$userId');

    final friendIds = <String>{};
    for (final row in friendships as List) {
      friendIds.add(
        row['requester_id'] == userId
            ? row['addressee_id'] as String
            : row['requester_id'] as String,
      );
    }
    if (friendIds.isEmpty) return [];

    final profiles = await _client
        .from('profiles')
        .select('id, username, avatar_url')
        .inFilter('id', friendIds.toList());

    final profileById = <String, Map<String, dynamic>>{};
    for (final p in profiles as List) {
      final m = Map<String, dynamic>.from(p);
      profileById[m['id'] as String] = m;
    }

    final out = <WildlifeFriendStat>[];
    for (final friendId in friendIds) {
      final rows = await _client
          .from('collection_items')
          .select('id, metadata, games_played')
          .eq('added_by', friendId)
          .eq('category', CollectionCategory.wildlife.dbValue)
          .eq('is_wishlist', false);

      final items = (rows as List)
          .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
          .toList();

      var obs = 0;
      final byRealm = <WildlifeRealm, int>{};
      for (final item in items) {
        final count = item.gamesPlayed ?? 0;
        if (count <= 0) continue;
        obs += count;
        final realm = WildlifeRealm.fromDb(
          item.metadata?['wildlife_realm'] as String?,
        );
        byRealm[realm] = (byRealm[realm] ?? 0) + 1;
      }

      final profile = profileById[friendId];
      out.add(
        WildlifeFriendStat(
          profileId: friendId,
          username: profile?['username'] as String? ?? 'Ami',
          avatarUrl: profile?['avatar_url'] as String?,
          speciesCount: items.where((i) => (i.gamesPlayed ?? 0) > 0).length,
          observationCount: obs,
          speciesByRealm: byRealm,
        ),
      );
    }

    out.sort((a, b) => b.speciesCount.compareTo(a.speciesCount));
    return out;
  }

  Future<WildlifeObservation?> addObservation({
    required String itemId,
    required DateTime observedAt,
    String? note,
    String? photoUrl,
    double? latitude,
    double? longitude,
    String? placeLabel,
  }) async {
    final id = _userId;
    if (id == null) return null;
    final row = await _client
        .from('wildlife_observations')
        .insert({
          'item_id': itemId,
          'user_id': id,
          'observed_at': observedAt.toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          if (photoUrl != null) 'photo_url': photoUrl,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (placeLabel != null) 'place_label': placeLabel,
        })
        .select()
        .single();
    return WildlifeObservation.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteObservation(String id) async {
    await _client.from('wildlife_observations').delete().eq('id', id);
  }
}
