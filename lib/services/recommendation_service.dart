import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/collection_item_filters.dart';
import '../utils/collection_item_scope.dart';
import 'friend_ratings_service.dart';
import 'friend_service.dart';

class Recommendation {
  final String title;
  final CollectionCategory category;
  final String reason;
  final String? friendUsername;
  final int? friendRating;
  final String? catalogKey;

  const Recommendation({
    required this.title,
    required this.category,
    required this.reason,
    this.friendUsername,
    this.friendRating,
    this.catalogKey,
  });
}

/// Propositions transverses basées sur notes élevées (soi + amis).
class RecommendationService {
  final _client = Supabase.instance.client;
  final _friends = FriendService();

  Future<List<Recommendation>> generate({int limit = 8}) async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return [];

    final mineRows = await CollectionItemScope.personal(
      _client.from('collection_items').select(
        'title, category, rating, metadata, is_wishlist, is_sold, is_for_sale',
      ),
      userId: userId,
    );

    final ownedKeys = <String>{};
    for (final row in mineRows as List) {
      final item = CollectionItem.fromJson(Map<String, dynamic>.from(row));
      if (!isActiveCollectionItem(item) && !(item.isWishlist)) continue;
      final key = FriendRatingsService.catalogKey(item);
      if (key != null) ownedKeys.add(key);
    }

    final friendIds = await _friends.listFriendProfileIds();
    if (friendIds.isEmpty) return _fromMyHighRatings(mineRows, ownedKeys, limit);

    final friendRows = await _client
        .from('collection_items')
        .select(
          'title, category, rating, review, metadata, added_by, profiles(username)',
        )
        .inFilter('added_by', friendIds)
        .gte('rating', 4)
        .eq('is_wishlist', false);

    final candidates = <Recommendation>[];
    final seen = <String>{};

    for (final raw in friendRows as List) {
      final row = Map<String, dynamic>.from(raw);
      final item = CollectionItem.fromJson(row);
      if (!isActiveCollectionItem(item)) continue;
      final key = FriendRatingsService.catalogKey(item);
      if (key == null || ownedKeys.contains(key) || seen.contains(key)) {
        continue;
      }
      seen.add(key);

      final profile = row['profiles'];
      final username =
          profile is Map ? profile['username'] as String? ?? 'Un ami' : 'Un ami';
      final stars = (row['rating'] as num?)?.round() ?? 4;

      candidates.add(
        Recommendation(
          title: item.title,
          category: item.category,
          reason: '$username adore cet objet (${stars}★)',
          friendUsername: username,
          friendRating: stars,
          catalogKey: key,
        ),
      );
    }

    candidates.addAll(_fromMyHighRatings(mineRows, ownedKeys, limit));
    candidates.sort((a, b) => (b.friendRating ?? 0).compareTo(a.friendRating ?? 0));
    return candidates.take(limit).toList();
  }

  List<Recommendation> _fromMyHighRatings(
    List<dynamic> mineRows,
    Set<String> ownedKeys,
    int limit,
  ) {
    final out = <Recommendation>[];
    final categoryScores = <CollectionCategory, int>{};

    for (final row in mineRows) {
      final item = CollectionItem.fromJson(Map<String, dynamic>.from(row));
      final stars = item.rating?.round() ?? 0;
      if (stars < 4) continue;
      categoryScores[item.category] =
          (categoryScores[item.category] ?? 0) + stars;
    }

    if (categoryScores.isEmpty) return out;

    final top = categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in top.take(3)) {
      out.add(
        Recommendation(
          title: 'Explorer ${entry.key.label}',
          category: entry.key,
          reason: 'Tu notes souvent haut tes ${entry.key.label.toLowerCase()}',
        ),
      );
    }

    return out.take(limit).toList();
  }
}
