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

const _defaultLimit = 48;

void sortBggCatalogByPopularity(List<BggCatalogGame> games) {
  int rankValue(BggCatalogGame g) {
    final r = int.tryParse(g.bggRank ?? '');
    if (r == null || r <= 0 || r >= 999999) return 999999;
    return r;
  }

  games.sort((a, b) {
    final ra = rankValue(a);
    final rb = rankValue(b);
    if (ra != rb) return ra.compareTo(rb);
    final ha = int.tryParse(a.hotRank ?? '') ?? 999;
    final hb = int.tryParse(b.hotRank ?? '') ?? 999;
    if (ha != hb) return ha.compareTo(hb);
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
}

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

  Future<List<BggCatalogGame>> _finalize(
    List<Map<String, String>> raw, {
    required Set<String> owned,
    int limit = _defaultLimit,
    String? Function(Map<String, String> map)? subtitleFor,
  }) async {
    final enriched = await BggService.enrichGameMaps(raw);
    final games = enriched
        .map(
          (m) => BggCatalogGame.fromBggMap(
            m,
            subtitle: subtitleFor != null ? subtitleFor(m) : null,
          ),
        )
        .where((g) => g.title.isNotEmpty && !_isOwned(g, owned))
        .toList();
    final deduped = _dedupe(games);
    sortBggCatalogByPopularity(deduped);
    return deduped.take(limit).toList();
  }

  Future<List<BggCatalogGame>> fetchPopular({int limit = _defaultLimit}) async {
    final owned = await _ownedKeys();
    final raw = <Map<String, String>>[];

    raw.addAll(await BggService.fetchHotBoardgames());

    for (final (en, _) in boardgameDiscoveryGenres.take(5)) {
      final hits = await BggService.searchGames(
        en,
        sort: BggSearchSort.popularity,
      );
      raw.addAll(hits.take(12));
    }

    return _finalize(raw, owned: owned, limit: limit);
  }

  Future<List<BggCatalogGame>> fetchFriendsLove({int limit = _defaultLimit}) async {
    final owned = await _ownedKeys();
    final raw = <Map<String, String>>[];
    final subtitles = <String, String>{};

    final suggestions =
        await _suggestions.fetchBoardgameSuggestions(limit: limit + 12);
    for (final s in suggestions) {
      if (s.bggId != null && s.bggId!.isNotEmpty) {
        raw.add({
          'id': s.bggId!,
          'title': s.title,
          if (s.imageUrl != null && s.imageUrl!.isNotEmpty)
            'image_url': s.imageUrl!,
        });
        subtitles[s.bggId!] = s.reason;
        continue;
      }
      final hits = await BggService.searchGames(
        s.title,
        sort: BggSearchSort.smart,
      );
      if (hits.isEmpty) continue;
      final hit = Map<String, String>.from(hits.first);
      hit['title'] = s.title;
      if (s.imageUrl != null && s.imageUrl!.isNotEmpty) {
        hit['image_url'] = s.imageUrl!;
      }
      final id = hit['id'] ?? '';
      if (id.isNotEmpty) subtitles[id] = s.reason;
      raw.add(hit);
    }

    final enriched = await BggService.enrichGameMaps(raw);
    final games = enriched
        .map((m) {
          final id = m['id'] ?? '';
          return BggCatalogGame.fromBggMap(
            m,
            subtitle: subtitles[id] ?? m['title'],
          );
        })
        .where((g) => g.title.isNotEmpty && !_isOwned(g, owned))
        .toList();

    final deduped = _dedupe(games);
    sortBggCatalogByPopularity(deduped);
    return deduped.take(limit).toList();
  }

  Future<List<BggCatalogGame>> fetchForYou({int limit = _defaultLimit}) async {
    final owned = await _ownedKeys();
    final raw = <Map<String, String>>[];
    final subtitles = <String, String>{};

    final friends =
        await _suggestions.fetchBoardgameSuggestions(limit: 16);
    for (final s in friends) {
      if (s.bggId != null && s.bggId!.isNotEmpty) {
        raw.add({
          'id': s.bggId!,
          'title': s.title,
          if (s.imageUrl != null && s.imageUrl!.isNotEmpty)
            'image_url': s.imageUrl!,
        });
        subtitles[s.bggId!] = s.reason;
      } else {
        final hits = await BggService.searchGames(
          s.title,
          sort: BggSearchSort.smart,
        );
        if (hits.isEmpty) continue;
        final hit = Map<String, String>.from(hits.first);
        hit['title'] = s.title;
        subtitles[hit['id'] ?? ''] = s.reason;
        raw.add(hit);
      }
    }

    final myGenres = await _myTopGenres();
    final genresToQuery = myGenres.isNotEmpty
        ? myGenres
        : ['Strategy', 'Family', 'Party'];

    for (final genre in genresToQuery) {
      final hits = await BggService.searchGames(
        genre,
        sort: BggSearchSort.popularity,
      );
      for (final h in hits.take(14)) {
        final id = h['id'] ?? '';
        if (id.isNotEmpty) {
          subtitles.putIfAbsent(
            id,
            () => myGenres.isNotEmpty
                ? 'Populaire en $genre'
                : 'Souvent aimé · $genre',
          );
        }
        raw.add(h);
      }
    }

    final hot = await BggService.fetchHotBoardgames();
    for (final h in hot.take(20)) {
      final id = h['id'] ?? '';
      if (id.isNotEmpty) {
        subtitles.putIfAbsent(id, () => 'Tendance BGG');
      }
      raw.add(h);
    }

    final enriched = await BggService.enrichGameMaps(raw);
    final games = enriched
        .map((m) {
          final id = m['id'] ?? '';
          return BggCatalogGame.fromBggMap(
            m,
            subtitle: subtitles[id],
          );
        })
        .where((g) => g.title.isNotEmpty && !_isOwned(g, owned))
        .toList();

    final deduped = _dedupe(games);
    sortBggCatalogByPopularity(deduped);
    return deduped.take(limit).toList();
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
    return sorted.map((e) => e.key).take(4).toList();
  }

  Future<List<BggCatalogGame>> search(
    String query, {
    int limit = _defaultLimit,
  }) async {
    final owned = await _ownedKeys();
    final hits = await BggService.searchGames(
      query,
      sort: BggSearchSort.smart,
    );
    return _finalize(hits, owned: owned, limit: limit);
  }

  Future<List<BggCatalogGame>> fetchByGenre(
    String genreEn, {
    int limit = _defaultLimit,
  }) async {
    final owned = await _ownedKeys();
    final hits = await BggService.searchGames(
      genreEn,
      sort: BggSearchSort.popularity,
    );
    return _finalize(
      hits,
      owned: owned,
      limit: limit,
      subtitleFor: (_) => genreEn,
    );
  }
}
