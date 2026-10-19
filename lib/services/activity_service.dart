import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_event.dart';

class ActivityService {
  final _client = Supabase.instance.client;

  Future<Map<String, Map<String, int>>> fetchReactionCounts(
    List<String> eventIds,
  ) async {
    if (eventIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('activity_reactions')
          .select('event_id, emoji')
          .inFilter('event_id', eventIds);
      final counts = <String, Map<String, int>>{};
      for (final row in rows as List) {
        final id = row['event_id']?.toString();
        final emoji = row['emoji']?.toString();
        if (id == null || emoji == null) continue;
        final bucket = counts.putIfAbsent(id, () => {});
        bucket[emoji] = (bucket[emoji] ?? 0) + 1;
      }
      return counts;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> fetchMyReactions(List<String> eventIds) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || eventIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('activity_reactions')
          .select('event_id, emoji')
          .eq('user_id', userId)
          .inFilter('event_id', eventIds);
      return {
        for (final row in rows as List)
          if (row['event_id'] != null && row['emoji'] != null)
            row['event_id'].toString(): row['emoji'].toString(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> setReaction(String eventId, String? emoji) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    if (emoji == null) {
      await _client
          .from('activity_reactions')
          .delete()
          .eq('event_id', eventId)
          .eq('user_id', userId);
      return;
    }
    await _client.from('activity_reactions').upsert({
      'event_id': eventId,
      'user_id': userId,
      'emoji': emoji,
    });
  }

  Future<void> logTrophiesUpdated() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('activity_events').insert({
      'actor_id': userId,
      'event_type': 'trophies_updated',
    });
  }

  /// Un ami identifié a modifié une partie dont je suis le propriétaire.
  /// Regroupé sur 15 minutes par objet pour éviter le spam.
  Future<void> logPlayEdited({
    required String itemId,
    required String? ownerId,
    required String itemTitle,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null || ownerId == null || ownerId.isEmpty || me == ownerId) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = 'play_edit_notify_$itemId';
    final last = prefs.getInt(key) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(minutes: 15).inMilliseconds) return;
    await prefs.setInt(key, now);
    try {
      await _client.from('activity_events').insert({
        'actor_id': me,
        'event_type': 'play_edited',
        'item_id': itemId,
        'payload': {'title': itemTitle},
      });
    } catch (_) {
      await prefs.remove(key);
    }
  }

  Future<List<ActivityEvent>> fetchFriendsFeed({int limit = 40}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final friendships = await _client
        .from('friendships')
        .select('requester_id, addressee_id')
        .eq('status', 'accepted')
        .eq('share_collections', true)
        .or('requester_id.eq.$userId,addressee_id.eq.$userId');

    // Inclut toujours mes propres événements (réactions testables à 1 compte).
    final actorIdsFilter = <String>{userId};
    for (final row in friendships as List) {
      final r = row['requester_id'] as String;
      final a = row['addressee_id'] as String;
      actorIdsFilter.add(r == userId ? a : r);
    }

    final rows = await _client
        .from('activity_events')
        .select('id, actor_id, event_type, item_id, payload, created_at')
        .inFilter('actor_id', actorIdsFilter.toList())
        .order('created_at', ascending: false)
        .limit(limit);

    final list = rows as List;
    if (list.isEmpty) return [];

    final actorIds = list.map((r) => r['actor_id'] as String).toSet();
    final itemIds = list
        .map((r) => r['item_id'] as String?)
        .whereType<String>()
        .toSet();

    final profiles = await _client
        .from('profiles')
        .select('id, username, avatar_url, accent_color')
        .inFilter('id', actorIds.toList());
    final profileById = {
      for (final p in profiles as List)
        p['id'] as String: Map<String, dynamic>.from(p),
    };

    final itemById = <String, Map<String, dynamic>>{};
    if (itemIds.isNotEmpty) {
      final items = await _client
          .from('collection_items')
          .select('id, title, image_url, category')
          .inFilter('id', itemIds.toList());
      for (final it in items as List) {
        itemById[it['id'] as String] = Map<String, dynamic>.from(it);
      }
    }

    return [
      for (final row in list) ...[
        () {
          final map = Map<String, dynamic>.from(row);
          final actorId = map['actor_id'] as String;
          final p = profileById[actorId];
          final itemId = map['item_id'] as String?;
          final it = itemId != null ? itemById[itemId] : null;
          final payload = map['payload'];
          double? rating;
          if (payload is Map && payload['rating'] != null) {
            rating = (payload['rating'] as num).toDouble();
          }
          return ActivityEvent(
            id: map['id'] as String,
            actorId: actorId,
            actorUsername: p?['username'] as String? ?? 'Ami',
            actorAvatarUrl: p?['avatar_url'] as String?,
            actorAccentColor: p?['accent_color'] as String?,
            eventType: map['event_type'] as String,
            itemId: itemId,
            itemTitle: it?['title'] as String?,
            itemImageUrl: it?['image_url'] as String?,
            itemCategory: it?['category'] as String?,
            rating: rating,
            createdAt: DateTime.parse(map['created_at'] as String),
          );
        }(),
      ],
    ];
  }
}
