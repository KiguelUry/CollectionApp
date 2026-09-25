import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/collection_item_filters.dart';
import 'friend_service.dart';

/// Jeu vidéo récemment ajouté par un ami.
class FriendRecentVideogame {
  final String title;
  final String? imageUrl;
  final String? rawgId;
  final String? platform;
  final String friendUsername;
  final DateTime addedAt;

  const FriendRecentVideogame({
    required this.title,
    this.imageUrl,
    this.rawgId,
    this.platform,
    required this.friendUsername,
    required this.addedAt,
  });

  Map<String, String> toCatalogHit() => {
        'title': title,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl!,
        if (rawgId != null && rawgId!.isNotEmpty) 'rawg_id': rawgId!,
        if (platform != null && platform!.isNotEmpty) 'platform': platform!,
        'source': 'friend',
      };
}

class FriendVideogameFeedService {
  final _client = Supabase.instance.client;
  final _friends = FriendService();

  Future<List<FriendRecentVideogame>> fetchRecentFriendAdds({
    int limit = 80,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final friendRows = await _friends.fetchFriends();
    if (friendRows.isEmpty) return [];

    final byId = <String, Map<String, dynamic>>{
      for (final f in friendRows) (f['profile_id'] as String? ?? ''): f,
    }..remove('');

    final feeds = await Future.wait(
      byId.keys.map((friendId) async {
        try {
          final items = await _friends.fetchFriendRecentByCategory(
            friendId,
            CollectionCategory.videogame,
            limit: 24,
          );
          final username =
              byId[friendId]?['username']?.toString() ?? 'Un ami';
          return (username, items);
        } catch (_) {
          return ('', <CollectionItem>[]);
        }
      }),
    );

    final merged = <String, FriendRecentVideogame>{};
    for (final (username, items) in feeds) {
      if (username.isEmpty) continue;
      for (final item in items) {
        if (!isActiveCollectionItem(item)) continue;
        final addedAt =
            item.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rawgId = item.metadata?['rawg_id']?.toString();
        final key = (rawgId != null && rawgId.isNotEmpty)
            ? rawgId
            : item.title.trim().toLowerCase();
        if (key.isEmpty) continue;

        final existing = merged[key];
        if (existing == null || addedAt.isAfter(existing.addedAt)) {
          merged[key] = FriendRecentVideogame(
            title: item.title,
            imageUrl: item.imageUrl,
            rawgId: rawgId,
            platform: item.metadata?['platform']?.toString(),
            friendUsername: username,
            addedAt: addedAt,
          );
        }
      }
    }

    final list = merged.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list.take(limit).toList();
  }
}
