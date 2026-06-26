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

    final rows = await _fetchRatedFriendItems(friendIds);
    if (rows.isEmpty) return [];

    final profiles = await _fetchProfilesForRows(rows);

    final out = <FriendRatingEntry>[];
    for (final row in rows) {
      final rating = row['rating'];
      if (rating == null) continue;
      final stars = rating is num ? rating.round() : int.tryParse('$rating');
      if (stars == null || stars < 1) continue;

      final friendItem = CollectionItem.fromJson(row);
      if (catalogKey(friendItem) != key) continue;

      final profileId = row['added_by'] as String?;
      if (profileId == null) continue;

      final profile = _profileFromRow(row) ?? profiles[profileId];
      out.add(
        FriendRatingEntry(
          profileId: profileId,
          username: profile?['username'] as String? ?? 'Ami',
          avatarUrl: profile?['avatar_url'] as String?,
          rating: stars.clamp(1, 5),
          review: row['review'] as String?,
          itemTitle: row['title'] as String? ?? friendItem.title,
        ),
      );
    }

    out.sort((a, b) => b.rating.compareTo(a.rating));
    return out;
  }

  Future<List<Map<String, dynamic>>> _fetchRatedFriendItems(
    List<String> friendIds,
  ) async {
    const columns =
        'title, rating, review, metadata, category, added_by';

    try {
      final rows = await _client
          .from('collection_items')
          .select('$columns, ${SupabaseEmbeds.addedByProfile}')
          .inFilter('added_by', friendIds)
          .not('rating', 'is', null);
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } on PostgrestException {
      final rows = await _client
          .from('collection_items')
          .select(columns)
          .inFilter('added_by', friendIds)
          .not('rating', 'is', null);
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    }
  }

  Map<String, dynamic>? _profileFromRow(Map<String, dynamic> row) {
    final profile = row['profiles'];
    if (profile is Map) {
      return Map<String, dynamic>.from(profile);
    }
    return null;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfilesForRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final missing = <String>{};
    for (final row in rows) {
      if (_profileFromRow(row) != null) continue;
      final id = row['added_by'] as String?;
      if (id != null) missing.add(id);
    }
    if (missing.isEmpty) return {};

    try {
      final result = await _client
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', missing.toList());
      final map = <String, Map<String, dynamic>>{};
      for (final row in result as List) {
        final m = Map<String, dynamic>.from(row as Map);
        final id = m['id'] as String?;
        if (id != null) map[id] = m;
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
