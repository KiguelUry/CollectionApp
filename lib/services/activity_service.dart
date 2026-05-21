import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_event.dart';

class ActivityService {
  final _client = Supabase.instance.client;

  Future<void> logTrophiesUpdated() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('activity_events').insert({
      'actor_id': userId,
      'event_type': 'trophies_updated',
    });
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

    final friendIds = <String>{};
    for (final row in friendships as List) {
      final r = row['requester_id'] as String;
      final a = row['addressee_id'] as String;
      friendIds.add(r == userId ? a : r);
    }
    if (friendIds.isEmpty) return [];

    final rows = await _client
        .from('activity_events')
        .select('id, actor_id, event_type, item_id, payload, created_at')
        .inFilter('actor_id', friendIds.toList())
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
