import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bgg_catalog_game.dart';
import '../models/collection_category.dart';
import '../utils/boardgame_genres.dart';
import '../services/bgg_service.dart';
import '../services/wishlist_suggestion_service.dart';

/// Genres BGG courants pour la découverte par tuile.
const boardgameDiscoveryGenres = <(String en, String fr)>[
  ('Strategy', 'Stratégie'),
  ('Family', 'Familial'),
  ('Party', 'Ambiance'),
  ('Cooperative', 'Coopératif'),
  ('Card Game', 'Jeu de cartes'),
  ('Economic', 'Économique'),
  ('Adventure', 'Aventure'),
  ('Abstract', 'Abstrait'),
];

class BoardgameDiscoveryService {
  final _suggestions = WishlistSuggestionService();
  final _client = Supabase.instance.client;

  Future<Set<String>> _ownedKeys() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('title, metadata')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    final keys = <String>{};
    for (final row in rows as List) {
      final title = (row['title'] as String?)?.trim().toLowerCase() ?? '';
      if (title.isNotEmpty) keys.add(title);
      final bggId = (row['metadata'] as Map<String, dynamic>?)?['bgg_id']
          ?.toString();
      if (bggId != null && bggId.isNotEmpty) keys.add(bggId);
    }
    return keys;
  }

  bool _isOwned(BggCatalogGame g, Set<String> owned) {
    if (g.bggId.isNotEmpty && owned.contains(g.bggId)) return true;
    return owned.contains(g.title.trim().toLowerCase());
  }

  List<BggCatalogGame> _dedupe(List<BggCatalogGame> list) {
    final seen = <String>{};
    final out = <BggCatalogGame>[];
    for (final g in list) {
      final key = g.bggId.isNotEmpty
          ? g.bggId
          : g.title.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(g);
    }
    return out;
  }

  Future<List<BggCatalogGame>> fetchPopular({int limit = 24}) async {
    final hot = await BggService.fetchHotBoardgames();
    final owned = await _ownedKeys();
    return _dedupe(
      hot
          .map((m) => BggCatalogGame.fromBggMap(m))
          .where((g) => g.title.isNotEmpty && !_isOwned(g, owned))
          .toList(),
    ).take(limit).toList();
  }

  Future<List<BggCatalogGame>> fetchFriendsLove({int limit = 24}) async {
    final owned = await _ownedKeys();
    final suggestions =
        await _suggestions.fetchBoardgameSuggestions(limit: limit + 10);
    return _dedupe(
      suggestions
          .map(
            (s) => BggCatalogGame(
              bggId: s.bggId ?? '',
              title: s.title,
              imageUrl: s.imageUrl,
              subtitle: s.reason,
              genres: s.genres,
            ),
          )
          .where((g) => !_isOwned(g, owned))
          .toList(),
    ).take(limit).toList();
  }

  Future<List<BggCatalogGame>> fetchForYou({int limit = 24}) async {
    final owned = await _ownedKeys();
    final out = <BggCatalogGame>[];

    final friends = await _suggestions.fetchBoardgameSuggestions(limit: 12);
    for (final s in friends) {
      out.add(
        BggCatalogGame(
          bggId: s.bggId ?? '',
          title: s.title,
          imageUrl: s.imageUrl,
          subtitle: s.reason,
          genres: s.genres,
        ),
      );
    }

    final myGenres = await _myTopGenres();
    final hot = await BggService.fetchHotBoardgames();
    for (final m in hot) {
      final g = BggCatalogGame.fromBggMap(m);
      if (_isOwned(g, owned)) continue;
      if (myGenres.isNotEmpty) {
        final genreHint = myGenres.first;
        out.add(
          BggCatalogGame(
            bggId: g.bggId,
            title: g.title,
            imageUrl: g.imageUrl,
            year: g.year,
            bggRank: g.bggRank,
            hotRank: g.hotRank,
            subtitle: 'Tendance BGG · tu aimes $genreHint',
          ),
        );
      } else {
        out.add(g);
      }
      if (out.length >= limit + 8) break;
    }

    if (out.length < 8) {
      final search = await BggService.searchGames('board game');
      for (final m in search) {
        final g = BggCatalogGame.fromBggMap(m);
        if (!_isOwned(g, owned)) out.add(g);
        if (out.length >= limit + 4) break;
      }
    }

    return _dedupe(out).take(limit).toList();
  }

  Future<List<String>> _myTopGenres() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await _client
        .from('collection_items')
        .select('metadata')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    final scores = <String, int>{};
    for (final row in rows as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      for (final g in boardgameGenresFromMetadata(meta)) {
        scores[g] = (scores[g] ?? 0) + 1;
      }
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).take(3).toList();
  }

  Future<List<BggCatalogGame>> search(String query, {int limit = 30}) async {
    final owned = await _ownedKeys();
    final hits = await BggService.searchGames(query);
    return _dedupe(
      hits
          .map((m) => BggCatalogGame.fromBggMap(m))
          .where((g) => g.title.isNotEmpty && !_isOwned(g, owned))
          .toList(),
    ).take(limit).toList();
  }

  Future<List<BggCatalogGame>> fetchByGenre(
    String genreEn, {
    int limit = 24,
  }) async {
    final owned = await _ownedKeys();
    final hits = await BggService.searchGames(genreEn);
    return _dedupe(
      hits
          .map(
            (m) => BggCatalogGame.fromBggMap(
              m,
              subtitle: genreEn,
            ),
          )
          .where((g) => g.title.isNotEmpty && !_isOwned(g, owned))
          .toList(),
    ).take(limit).toList();
  }
}
