import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/supabase_embeds.dart';
import 'friend_service.dart';

/// Note et avis laissés par les amis sur le même objet (catalogue).
class FriendRatingEntry {
  final String profileId;
  final String username;
  final String? avatarUrl;
  final int rating;
  final String? review;
  final String itemTitle;

  const FriendRatingEntry({
    required this.profileId,
    required this.username,
    this.avatarUrl,
    required this.rating,
    this.review,
    required this.itemTitle,
  });
}

class FriendRatingsService {
  final _client = Supabase.instance.client;
  final _friends = FriendService();

  static String? catalogKey(CollectionItem item) {
    final meta = item.metadata ?? {};
    final bgg = meta['bgg_id']?.toString();
    if (bgg != null && bgg.isNotEmpty) return 'bgg:$bgg';
    final discogs = meta['discogs_release_id']?.toString();
    if (discogs != null && discogs.isNotEmpty) return 'discogs:$discogs';
    final isbn = meta['isbn']?.toString() ?? meta['isbn13']?.toString();
    if (isbn != null && isbn.isNotEmpty) return 'isbn:$isbn';
    final igdb = meta['igdb_id']?.toString();
    if (igdb != null && igdb.isNotEmpty) return 'igdb:$igdb';
    return '${item.category.dbValue}|${item.title.trim().toLowerCase()}';
  }

  Future<List<FriendRatingEntry>> fetchFriendRatingsForItem(
    CollectionItem item,
  ) async {
    final key = catalogKey(item);
    if (key == null) return [];

    final friendIds = await _friends.listFriendProfileIds();
    if (friendIds.isEmpty) return [];

    final rows = await _client
        .from('collection_items')
        .select(
          'title, rating, review, metadata, category, added_by, '
          '${SupabaseEmbeds.addedByProfile}',
        )
        .inFilter('added_by', friendIds)
        .not('rating', 'is', null);

    final out = <FriendRatingEntry>[];
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw);
      final rating = row['rating'];
      if (rating == null) continue;
      final stars = rating is num ? rating.round() : int.tryParse('$rating');
      if (stars == null || stars < 1) continue;

      final friendItem = CollectionItem.fromJson(row);
      if (catalogKey(friendItem) != key) continue;

      final profile = row['profiles'];
      if (profile is! Map) continue;
      out.add(
        FriendRatingEntry(
          profileId: row['added_by'] as String,
          username: profile['username'] as String? ?? 'Ami',
          avatarUrl: profile['avatar_url'] as String?,
          rating: stars.clamp(1, 5),
          review: row['review'] as String?,
          itemTitle: row['title'] as String? ?? friendItem.title,
        ),
      );
    }

    out.sort((a, b) => b.rating.compareTo(a.rating));
    return out;
  }
}
