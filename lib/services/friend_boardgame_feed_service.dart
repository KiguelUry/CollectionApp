import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/collection_item_filters.dart';
import 'friend_service.dart';

/// Jeu récemment ajouté par un ami (feed social).
class FriendRecentBoardgame {
  final String title;
  final String? imageUrl;
  final String? bggId;
  final String friendUsername;
  final DateTime addedAt;

  const FriendRecentBoardgame({
    required this.title,
    this.imageUrl,
    this.bggId,
    required this.friendUsername,
    required this.addedAt,
  });

  String get catalogKey =>
      (bggId != null && bggId!.isNotEmpty)
          ? bggId!
          : title.trim().toLowerCase();
}

class FriendBoardgameFeedService {
  final _client = Supabase.instance.client;
  final _friends = FriendService();

  Future<List<FriendRecentBoardgame>> fetchRecentFriendAdds({
    int limit = 80,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final friendRows = await _friends.fetchFriends();
    if (friendRows.isEmpty) return [];

    final byId = <String, Map<String, dynamic>>{
      for (final f in friendRows)
        (f['profile_id'] as String? ?? ''): f,
    }..remove('');

    final feeds = await Future.wait(
      byId.keys.map((friendId) async {
        try {
          final items = await _friends.fetchFriendRecentBoardgames(
            friendId,
            limit: 24,
          );
          final username =
              byId[friendId]?['username']?.toString() ?? 'Un ami';
          return (friendId, username, items);
        } catch (_) {
          return (friendId, '', <CollectionItem>[]);
        }
      }),
    );

    final merged = <String, FriendRecentBoardgame>{};
    for (final (_, username, items) in feeds) {
      if (username.isEmpty) continue;
      for (final item in items) {
        if (item.category != CollectionCategory.boardgame) continue;
        if (!isActiveCollectionItem(item)) continue;
        final addedAt = item.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bggId = item.metadata?['bgg_id']?.toString();
        final key = (bggId != null && bggId.isNotEmpty)
            ? bggId
            : item.title.trim().toLowerCase();
        if (key.isEmpty) continue;

        final existing = merged[key];
        if (existing == null || addedAt.isAfter(existing.addedAt)) {
          merged[key] = FriendRecentBoardgame(
            title: item.title,
            imageUrl: item.imageUrl,
            bggId: bggId,
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
