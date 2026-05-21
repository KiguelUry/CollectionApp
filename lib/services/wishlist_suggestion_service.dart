import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../utils/boardgame_genres.dart';
import '../utils/collection_item_filters.dart';
import 'friend_service.dart';

/// Suggestion « Tu pourrais ajouter… » basée sur les jeux bien notés des amis.
class WishlistSuggestion {
  final String title;
  final String? imageUrl;
  final String reason;
  final String? bggId;
  final List<String> genres;

  const WishlistSuggestion({
    required this.title,
    this.imageUrl,
    required this.reason,
    this.bggId,
    this.genres = const [],
  });
}

class WishlistSuggestionService {
  final _client = Supabase.instance.client;
  final _friends = FriendService();

  Future<List<WishlistSuggestion>> fetchBoardgameSuggestions({
    int limit = 5,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final friendIds = await _friends.listFriendProfileIds();
    if (friendIds.isEmpty) return [];

    final myRows = await _client
        .from('collection_items')
        .select('title, is_wishlist, metadata')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    final ownedTitles = <String>{};
    for (final row in myRows as List) {
      final t = (row['title'] as String?)?.trim().toLowerCase();
      if (t != null && t.isNotEmpty) ownedTitles.add(t);
    }

    final genreScores = <String, int>{};
    final candidates = <Map<String, dynamic>>[];

    for (final friendId in friendIds) {
      try {
        if (!await _friends.canViewFriendCollection(friendId)) continue;
        final rows = await _friends.fetchFriendCollectionItems(friendId);
        for (final item in rows) {
          if (item.category != CollectionCategory.boardgame) continue;
          if (item.isWishlist || !isActiveCollectionItem(item)) continue;
          if ((item.rating ?? 0) < 4) continue;

          final genres = boardgameGenresFromMetadata(item.metadata);
          for (final g in genres) {
            genreScores[g] = (genreScores[g] ?? 0) + 1;
          }

          final key = item.title.trim().toLowerCase();
          if (ownedTitles.contains(key)) continue;

          candidates.add({
            'title': item.title,
            'image_url': item.imageUrl,
            'rating': item.rating,
            'metadata': item.metadata,
            'genres': genres,
          });
        }
      } catch (_) {
        continue;
      }
    }

    if (candidates.isEmpty) return [];

    final topGenres = genreScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final favoriteGenre =
        topGenres.isEmpty ? null : topGenres.first.key;

    candidates.sort((a, b) {
      final ra = a['rating'] as double? ?? 0;
      final rb = b['rating'] as double? ?? 0;
      return rb.compareTo(ra);
    });

    final seen = <String>{};
    final out = <WishlistSuggestion>[];

    for (final c in candidates) {
      final title = c['title'] as String;
      final key = title.trim().toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);

      final genres = (c['genres'] as List).cast<String>();
      final meta = c['metadata'] as Map<String, dynamic>?;
      final bggId = meta?['bgg_id']?.toString();

      String reason;
      if (favoriteGenre != null &&
          genres.any((g) => g.toLowerCase() == favoriteGenre.toLowerCase())) {
        reason =
            'Tes amis aiment le genre « $favoriteGenre » — celui-ci est bien noté chez eux.';
      } else {
        reason = 'Un ami l\'a noté ${(c['rating'] as double?)?.toStringAsFixed(1) ?? '4'}+.';
      }

      out.add(WishlistSuggestion(
        title: title,
        imageUrl: c['image_url'] as String?,
        reason: reason,
        bggId: bggId,
        genres: genres,
      ));
      if (out.length >= limit) break;
    }

    return out;
  }
}
