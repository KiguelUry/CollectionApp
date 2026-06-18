import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/boardgame_curated_catalog.dart';
import '../models/bgg_catalog_game.dart';
import '../models/collection_category.dart';
import '../utils/boardgame_genres.dart';
import '../services/bgg_service.dart';
import '../services/friend_boardgame_feed_service.dart';

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

const catalogPageSize = 40;

int _rankValue(BggCatalogGame g) {
  final r = int.tryParse(g.bggRank ?? '');
  if (r == null || r <= 0 || r >= 999999) return 999999;
  return r;
}

void sortBggCatalogByPopularity(List<BggCatalogGame> games) {
  games.sort((a, b) {
    final ra = _rankValue(a);
    final rb = _rankValue(b);
    if (ra != rb) return ra.compareTo(rb);
    final ha = int.tryParse(a.hotRank ?? '') ?? 999;
    final hb = int.tryParse(b.hotRank ?? '') ?? 999;
    if (ha != hb) return ha.compareTo(hb);
    final ya = int.tryParse(a.year ?? '') ?? 0;
    final yb = int.tryParse(b.year ?? '') ?? 0;
    if (ya != yb) return yb.compareTo(ya);
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
}

void sortBggCatalogByHotAndRecency(List<BggCatalogGame> games) {
  games.sort((a, b) {
    final ha = int.tryParse(a.hotRank ?? '') ?? 999;
    final hb = int.tryParse(b.hotRank ?? '') ?? 999;
    if (ha != hb) return ha.compareTo(hb);
    final ra = _rankValue(a);
    final rb = _rankValue(b);
    if (ra != rb) return ra.compareTo(rb);
    final ya = int.tryParse(a.year ?? '') ?? 0;
    final yb = int.tryParse(b.year ?? '') ?? 0;
    return yb.compareTo(ya);
  });
}

bool isDiscoverableQuality(BggCatalogGame g) {
  final rank = _rankValue(g);
  if (rank < 8000) return true;
  final hot = int.tryParse(g.hotRank ?? '');
  if (hot != null && hot <= 50) return true;
  final year = int.tryParse(g.year ?? '');
  if (year != null && year >= 2012 && rank < 20000) return true;
  return false;
}

class BoardgameDiscoveryService {
  final _friendFeed = FriendBoardgameFeedService();
  final _client = Supabase.instance.client;

  List<BggCatalogGame> _dedupe(List<BggCatalogGame> list) {
    final seen = <String>{};
    final out = <BggCatalogGame>[];
    for (final g in list) {
      final key = g.catalogKey;
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(g);
    }
    return out;
  }

  List<BggCatalogGame> _mapsToGames(
    List<Map<String, String>> raw, {
    Map<String, String>? subtitles,
    Map<String, int>? addedAtMs,
  }) {
    return raw
        .map((m) {
          final id = m['id'] ?? '';
          return BggCatalogGame.fromBggMap(
            m,
            subtitle: subtitles?[id],
            addedAtMs: addedAtMs?[id],
          );
        })
        .where((g) => g.title.isNotEmpty)
        .toList();
  }

  Future<List<BggCatalogGame>> _fromIds(
    List<String> ids, {
    Map<String, String>? subtitles,
    bool qualityOnly = true,
    String? genreEn,
  }) async {
    if (ids.isEmpty) return [];
    final raw = await BggService.fetchGamesByIds(ids);
    final filteredRaw = genreEn != null && genreEn.isNotEmpty
        ? raw.where((m) => boardgameMapMatchesGenre(m, genreEn)).toList()
        : raw;
    var games = _mapsToGames(filteredRaw, subtitles: subtitles);
    games = _dedupe(games);
    if (qualityOnly) {
      games = games.where(isDiscoverableQuality).toList();
    }
    sortBggCatalogByPopularity(games);
    return games;
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

  /// Hot BGG + tops globaux, tri tendance puis popularité.
  Future<List<BggCatalogGame>> fetchPopular({int limit = 120}) async {
    final results = await Future.wait([
      BggService.fetchHotBoardgames(),
      _fromIds(boardgameGlobalTopIds, qualityOnly: true),
    ]);
    final hotMaps = results[0] as List<Map<String, String>>;
    final curated = results[1] as List<BggCatalogGame>;

    final hotGames = _dedupe(_mapsToGames(hotMaps));
    sortBggCatalogByHotAndRecency(hotGames);

    final merged = _dedupe([...hotGames, ...curated]);
    sortBggCatalogByHotAndRecency(merged);
    return merged.take(limit).toList();
  }

  /// Ajouts récents des amis, un jeu = le dernier ami à l'avoir ajouté.
  Future<List<BggCatalogGame>> fetchFriendRecentAdds({int limit = 80}) async {
    final recent = await _friendFeed.fetchRecentFriendAdds(limit: limit + 20);
    if (recent.isEmpty) return [];

    final needLookup = <FriendRecentBoardgame>[];
    final ready = <BggCatalogGame>[];

    for (final r in recent) {
      if (r.bggId != null && r.bggId!.isNotEmpty) {
        needLookup.add(r);
      } else {
        ready.add(
          BggCatalogGame(
            bggId: '',
            title: r.title,
            imageUrl: r.imageUrl,
            subtitle: 'Ajouté par ${r.friendUsername}',
            addedAtMs: r.addedAt.millisecondsSinceEpoch,
          ),
        );
      }
    }

    if (needLookup.isNotEmpty) {
      final ids = needLookup.map((r) => r.bggId!).toList();
      final subtitles = {
        for (final r in needLookup) r.bggId!: 'Ajouté par ${r.friendUsername}',
      };
      final addedAt = {
        for (final r in needLookup)
          r.bggId!: r.addedAt.millisecondsSinceEpoch,
      };
      final raw = await BggService.fetchGamesByIds(ids);
      ready.addAll(
        _mapsToGames(raw, subtitles: subtitles, addedAtMs: addedAt),
      );
    }

    final merged = _dedupe(ready);
    merged.sort((a, b) {
      final ta = a.addedAtMs ?? 0;
      final tb = b.addedAtMs ?? 0;
      if (ta != tb) return tb.compareTo(ta);
      return _rankValue(a).compareTo(_rankValue(b));
    });
    return merged.take(limit).toList();
  }

  Future<List<BggCatalogGame>> fetchForYou({int limit = 120}) async {
    final genres = await _myTopGenres();
    final genreKeys = genres.isNotEmpty
        ? genres
        : ['Strategy', 'Family', 'Party'];

    final idSet = <String>{};
    for (final g in genreKeys) {
      idSet.addAll(curatedIdsForGenre(g, max: 30));
    }
    idSet.addAll(boardgameGlobalTopIds.take(25));

    final results = await Future.wait([
      fetchFriendRecentAdds(limit: 24),
      _fromIds(idSet.toList(), qualityOnly: true),
      BggService.fetchHotBoardgames(),
    ]);

    final friends = results[0] as List<BggCatalogGame>;
    final curated = results[1] as List<BggCatalogGame>;
    final hotMaps = results[2] as List<Map<String, String>>;
    final hot = _dedupe(_mapsToGames(hotMaps));

    final genreLabels = {
      for (final g in genreKeys) g: 'Pour toi · $g',
    };

    final curatedLabeled = curated
        .map((g) {
          if (g.subtitle != null) return g;
          final match = genreKeys.firstOrNull;
          return g.copyWith(
            subtitle: match != null
                ? (genreLabels[match] ?? 'Populaire')
                : 'Populaire',
          );
        })
        .toList();

    final hotLabeled = hot
        .map((g) => g.copyWith(subtitle: g.subtitle ?? 'Tendance BGG'))
        .toList();

    final merged = _dedupe([...friends, ...curatedLabeled, ...hotLabeled]);
    sortBggCatalogByPopularity(merged);
    return merged.take(limit).toList();
  }

  Future<List<BggCatalogGame>> search(
    String query, {
    int limit = 80,
  }) async {
    final hits = await BggService.searchGames(
      query,
      sort: BggSearchSort.smart,
    );
    final games = _dedupe(_mapsToGames(hits));
    sortBggCatalogByPopularity(games);
    return games.take(limit).toList();
  }

  Future<List<BggCatalogGame>> fetchByGenre(
    String genreEn, {
    int limit = 120,
  }) async {
    final seedIds = <String>{
      ...curatedIdsForGenre(genreEn, max: 60),
      ...boardgameGlobalTopIds.take(35),
    }.toList();
    final subtitles = {for (final id in seedIds) id: genreEn};
    final games = await _fromIds(
      seedIds,
      genreEn: genreEn,
      subtitles: subtitles,
      qualityOnly: true,
    );
    return games.take(limit).toList();
  }
}
