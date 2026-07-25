import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../config/app_env.dart';
import '../config/supabase_public_config.dart';
import '../models/bgg_expansion.dart';
import '../utils/search_relevance.dart';

enum BggSearchSort {
  /// Pertinence du titre + popularité BGG (classement).
  smart,

  /// Classement BGG global (les plus connus en premier).
  popularity,

  /// Année de sortie la plus récente.
  recent,
}

class _CachedSearch {
  final List<Map<String, String>> games;
  final DateTime at;

  const _CachedSearch(this.games, this.at);
}

class _BggThingMeta {
  final int? rank;
  final String? thumbnail;
  final String? image;
  final String? title;
  final String? year;
  final List<String> categories;
  final double? avgRating;

  const _BggThingMeta({
    this.rank,
    this.thumbnail,
    this.image,
    this.title,
    this.year,
    this.categories = const [],
    this.avgRating,
  });
}

class BggService {
  static const _maxSearchResults = 50;
  /// Moins d'appels /thing (limite BGG ~429 si trop de requêtes).
  static const _maxMetaLookup = 24;
  static const _thingChunkSize = 8;
  static const _maxPollAttempts = 10;
  /// Jeux de société + JDR narratifs (ex. Alice is Missing) + extensions.
  static const _searchTypes = 'boardgame,rpgitem,boardgameexpansion';

  /// Sur le web : API JSON `bgg-api` (XML parsé côté serveur).
  static bool get _useWebJsonApi => kIsWeb;

  /// Recherche BGG : web via `bgg-api`, app native en direct.
  static bool get supportsWebSearch => !_useWebJsonApi || _webProxyReady;

  static bool get _webProxyReady {
    return AppEnv.supabaseUrl.isNotEmpty && AppEnv.supabaseAnonKey.isNotEmpty;
  }

  static bool get webBggAvailable => supportsWebSearch;

  static Uri _jsonApiUri(String action, Map<String, String> params) {
    final base = SupabasePublicConfig.url.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/functions/v1/bgg-api').replace(
      queryParameters: {'action': action, ...params},
    );
  }

  static Future<Map<String, dynamic>?> _jsonApiGet(
    String action,
    Map<String, String> params,
  ) async {
    if (!_webProxyReady) return null;
    try {
      final anon = AppEnv.supabaseAnonKey;
      // Firefox (ETP / bloqueurs) retire parfois Authorization cross-origin :
      // apikey en query + header suffit pour les Edge Functions publiques.
      final uri = _jsonApiUri(action, {
        ...params,
        if (_useWebJsonApi) 'apikey': anon,
      });
      final headers = <String, String>{
        'Accept': 'application/json',
        if (_useWebJsonApi) 'apikey': anon,
      };
      final response = await http.get(uri, headers: headers);
      if (response.statusCode != 200 || response.body.isEmpty) {
        lastSearchError = response.statusCode == 0
            ? 'Réseau bloqué. Vérifie la fonction bgg-api sur Supabase.'
            : 'BGG API ${response.statusCode}';
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final status = decoded['status']?.toString();
      if (status != null && status.isNotEmpty) {
        lastSearchStatus = status;
      }
      final err = decoded['error'];
      if (err != null) {
        lastSearchError = err.toString();
        return null;
      }
      return decoded;
    } catch (e) {
      lastSearchError = 'BGG API : $e';
      return null;
    }
  }

  static List<Map<String, String>> _gamesFromJsonList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((g) {
          final map = g.map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
          );
          if ((map['image_url'] ?? '').isEmpty &&
              (map['thumbnail_url'] ?? '').isNotEmpty) {
            map['image_url'] = map['thumbnail_url']!;
          }
          return map;
        })
        .where((g) => g['id']?.isNotEmpty == true)
        .toList();
  }

  /// Dernière erreur recherche (affichée sur le web en release).
  static String? lastSearchError;

  /// Message de progression (recherche, cache, retry 429…).
  static String? lastSearchStatus;

  /// Titres très courts que l’API search BGG rate souvent (clé = titre normalisé).
  static const _knownBggIdByNormTitle = <String, String>{
    'ra': '12',
  };

  static final _searchCache = <String, _CachedSearch>{};
  static const _searchCacheTtl = Duration(minutes: 15);
  static const _searchCacheMaxEntries = 48;
  static DateTime? _lastBggHttpAt;
  static const _minBggRequestGap = Duration(milliseconds: 320);

  static List<Map<String, String>>? _hotCache;
  static DateTime? _hotCacheAt;

  static Map<String, String> get _headers {
    final headers = <String, String>{
      'User-Agent': 'CollectionFamille/1.0',
      'Accept': 'application/xml',
    };
    final token = dotenv.env['BGG_APPLICATION_TOKEN']?.trim();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static String _searchCacheKey(String query, BggSearchSort sort) =>
      '${sort.name}:${query.toLowerCase().trim()}';

  static void _storeSearchCache(String key, List<Map<String, String>> games) {
    _searchCache[key] = _CachedSearch(
      games.map((g) => Map<String, String>.from(g)).toList(),
      DateTime.now(),
    );
    if (_searchCache.length <= _searchCacheMaxEntries) return;
    String? oldestKey;
    DateTime? oldestAt;
    for (final e in _searchCache.entries) {
      if (oldestAt == null || e.value.at.isBefore(oldestAt)) {
        oldestAt = e.value.at;
        oldestKey = e.key;
      }
    }
    if (oldestKey != null) _searchCache.remove(oldestKey);
  }

  static Future<void> _throttleBggRequest() async {
    final last = _lastBggHttpAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      final wait = _minBggRequestGap - elapsed;
      if (wait > Duration.zero) await Future.delayed(wait);
    }
    _lastBggHttpAt = DateTime.now();
  }

  /// L'API XML BGG répond souvent 202 (« Please try again ») : on réessaie.
  static Future<http.Response> _getWithRetry(Uri url) async {
    if (_useWebJsonApi) {
      return http.Response('', 503);
    }

    final target = url;
    final headers = _headers;

    http.Response? last;
    for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
      await _throttleBggRequest();
      last = await http.get(target, headers: headers);
      if (last.statusCode == 429) {
        lastSearchStatus =
            'BGG surchargé — nouvel essai (${attempt + 1}/$_maxPollAttempts)…';
        lastSearchError =
            'BGG limite les requêtes (trop d’appels). Nouvel essai automatique…';
        await Future.delayed(
          Duration(milliseconds: 900 + attempt * 700),
        );
        continue;
      }
      final pending = last.statusCode == 202 ||
          (last.statusCode == 200 &&
              last.body.contains('Please try again'));
      if (!pending) return last;
      await Future.delayed(
        Duration(milliseconds: 400 + attempt * 250),
      );
    }
    return last!;
  }

  static List<Map<String, String>> _parseSearchXmlItems(String body) {
    final document = _parseXmlDocument(body);
    if (document == null) return [];
    final candidates = <Map<String, String>>[];
    for (final node in document.findAllElements('item')) {
      if (candidates.length >= _maxSearchResults) break;
      final itemType = node.getAttribute('type') ?? '';
      if (!_isSearchableBggType(itemType)) continue;
      final id = node.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final year =
          node.findElements('yearpublished').firstOrNull?.getAttribute('value') ??
              '';
      candidates.add({
        'id': id,
        'title': _primaryTitle(node),
        'year': year,
        if (itemType.isNotEmpty) 'bgg_type': itemType,
      });
    }
    return candidates;
  }

  static bool _isSearchableBggType(String type) =>
      type == 'boardgame' ||
      type == 'rpgitem' ||
      type == 'boardgameexpansion';

  static Iterable<String> _exactQueryVariants(String query) sync* {
    final t = query.trim();
    if (t.isEmpty) return;
    yield t;
    final lower = t.toLowerCase();
    if (lower != t) yield lower;
    if (t.length <= 20) {
      final titleCased = lower.isEmpty
          ? lower
          : '${lower[0].toUpperCase()}${lower.substring(1)}';
      if (titleCased != t && titleCased != lower) yield titleCased;
    }
  }

  static Future<List<Map<String, String>>> _fetchExactSearchCandidates(
    String query, {
    String type = _searchTypes,
  }) async {
    var merged = <Map<String, String>>[];
    for (final variant in _exactQueryVariants(query)) {
      final exactUrl = Uri.https('boardgamegeek.com', '/xmlapi2/search', {
        'query': variant,
        'type': type,
        'exact': '1',
      });
      final exactResponse = await _getWithRetry(exactUrl);
      if (exactResponse.statusCode == 200 && exactResponse.body.isNotEmpty) {
        merged = _mergeSearchCandidates(
          merged,
          _parseSearchXmlItems(exactResponse.body),
        );
      }
    }
    return merged;
  }

  /// Recherche exacte jeux de société seuls (ex. « Ra » = id 12).
  static Future<List<Map<String, String>>> _fetchExactBoardgameCandidates(
    String query,
  ) =>
      _fetchExactSearchCandidates(query, type: 'boardgame');

  static Future<List<Map<String, String>>> _fetchKnownTitleHits(
    String query,
  ) async {
    final key = query.toLowerCase().trim();
    final id = _knownBggIdByNormTitle[key];
    if (id == null) return [];
    try {
      final meta = await _fetchThingMeta([id]);
      final m = meta[id];
      final title = m?.title;
      if (title == null || title.isEmpty) return [];
      return [
        {
          'id': id,
          'title': title,
          if (m?.year != null && m!.year!.isNotEmpty) 'year': m.year!,
          'bgg_type': 'boardgame',
          if (m?.rank != null) 'bgg_rank': m!.rank.toString(),
          if (m?.thumbnail != null && m!.thumbnail!.isNotEmpty)
            'image_url': m.thumbnail!,
        },
      ];
    } catch (_) {
      return [];
    }
  }

  static void _pinExactTitleMatches(
    List<Map<String, String>> items,
    String query,
  ) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return;
    final exact = <Map<String, String>>[];
    final rest = <Map<String, String>>[];
    for (final g in items) {
      final title = g['title']?.toLowerCase().trim() ?? '';
      if (title == q) {
        exact.add(g);
      } else {
        rest.add(g);
      }
    }
    if (exact.isEmpty) return;
    items
      ..clear()
      ..addAll(exact)
      ..addAll(rest);
  }

  static List<Map<String, String>> _mergeSearchCandidates(
    List<Map<String, String>> primary,
    List<Map<String, String>> secondary,
  ) {
    final seen = primary.map((g) => g['id']).whereType<String>().toSet();
    final out = [...primary];
    for (final g in secondary) {
      final id = g['id'];
      if (id == null || id.isEmpty || !seen.add(id)) continue;
      out.add(g);
      if (out.length >= _maxSearchResults) break;
    }
    return out;
  }

  /// Recherche xmlapi2 (+ exacte / titres connus pour courts type « Ra »).
  static Future<List<Map<String, String>>> _fetchSearchCandidates(
    String query,
  ) async {
    var candidates = <Map<String, String>>[];

    // Requêtes ≤3 car. : exact + fallback (évite le bruit et les 429).
    if (query.length <= 3) {
      candidates = await _fetchKnownTitleHits(query);
      candidates = _mergeSearchCandidates(
        candidates,
        await _fetchExactBoardgameCandidates(query),
      );
      candidates = _mergeSearchCandidates(
        candidates,
        await _fetchExactSearchCandidates(query),
      );
      return candidates;
    }

    final url = Uri.https('boardgamegeek.com', '/xmlapi2/search', {
      'query': query,
      'type': _searchTypes,
    });
    final response = await _getWithRetry(url);
    if (response.statusCode != 200 || response.body.isEmpty) {
      if (response.statusCode == 429) {
        lastSearchError =
            'BGG limite les requêtes (429). Réessaie dans quelques secondes.';
      } else if (response.statusCode != 0) {
        lastSearchError = 'BGG a répondu ${response.statusCode}';
      }
      candidates = await _fetchKnownTitleHits(query);
      if (candidates.isNotEmpty) return candidates;
      return [];
    }

    candidates = _parseSearchXmlItems(response.body);
    if (query.length <= 8) {
      candidates = _mergeSearchCandidates(
        await _fetchKnownTitleHits(query),
        candidates,
      );
      candidates = _mergeSearchCandidates(
        await _fetchExactBoardgameCandidates(query),
        candidates,
      );
      candidates = _mergeSearchCandidates(
        await _fetchExactSearchCandidates(query),
        candidates,
      );
    }
    return candidates;
  }

  static String _primaryTitle(XmlElement node) {
    for (final name in node.findElements('name')) {
      if (name.getAttribute('type') == 'primary') {
        return name.getAttribute('value') ?? 'Sans titre';
      }
    }
    return node.findElements('name').firstOrNull?.getAttribute('value') ??
        'Sans titre';
  }

  static Future<List<Map<String, String>>> searchGames(
    String query, {
    BggSearchSort sort = BggSearchSort.smart,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    lastSearchError = null;
    lastSearchStatus = 'Recherche sur BoardGameGeek…';
    if (!supportsWebSearch) {
      lastSearchError =
          'Recherche BGG indisponible : configure Supabase (fonction bgg-api).';
      lastSearchStatus = null;
      return [];
    }

    final cacheKey = _searchCacheKey(trimmed, sort);
    final cached = _searchCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _searchCacheTtl) {
      lastSearchStatus = 'Résultats en cache (moins d’appels BGG)';
      return cached.games
          .map((g) => Map<String, String>.from(g))
          .toList();
    }

    if (_useWebJsonApi) {
      final data = await _jsonApiGet('search', {
        'query': trimmed,
        'sort': switch (sort) {
          BggSearchSort.recent => 'recent',
          BggSearchSort.popularity => 'popularity',
          _ => 'smart',
        },
      });
      if (data == null) {
        lastSearchStatus = null;
        return [];
      }
      final games = _gamesFromJsonList(data['games']);
      if (games.isNotEmpty) {
        _storeSearchCache(cacheKey, games);
        if (data['cached'] == true) {
          lastSearchStatus = 'Résultats en cache (moins d’appels BGG)';
        } else {
          lastSearchStatus = null;
        }
      } else {
        lastSearchStatus = null;
      }
      return games;
    }

    try {
      final candidates = await _fetchSearchCandidates(trimmed);
      if (candidates.isEmpty) return [];

      sortByScore(
        candidates,
        (g) => titleRelevanceScore(g['title']!, trimmed),
      );

      final top = candidates.take(_maxMetaLookup).toList();
      Map<String, _BggThingMeta> meta = {};
      try {
        meta = await _fetchThingMeta(top.map((g) => g['id']!).toList());
      } catch (e) {
        if (kDebugMode) debugPrint('BGG thing (recherche) ignoré : $e');
      }

      final ranked = top.map((g) {
        final m = meta[g['id']];
        return {
          ...g,
          if (m?.rank != null) 'bgg_rank': m!.rank.toString(),
          if (m?.thumbnail != null && m!.thumbnail!.isNotEmpty)
            'image_url': m.thumbnail!,
        };
      }).toList();

      _sortResults(ranked, trimmed, sort, meta);
      _pinExactTitleMatches(ranked, trimmed);

      final results = ranked.take(40).toList();
      if (results.isNotEmpty) {
        _storeSearchCache(cacheKey, results);
        lastSearchStatus = null;
      }
      return results;
    } catch (e) {
      lastSearchError = 'Recherche BGG impossible : $e';
      lastSearchStatus = null;
      if (kDebugMode) debugPrint('Erreur recherche BGG: $e');
    }
    return [];
  }

  static XmlDocument? _parseXmlDocument(String body) {
    final trimmed = body.trim();
    if (!trimmed.startsWith('<')) {
      lastSearchError = trimmed.length > 160
          ? '${trimmed.substring(0, 160)}…'
          : (trimmed.isEmpty ? 'Réponse vide du proxy BGG' : trimmed);
      return null;
    }
    try {
      return XmlDocument.parse(trimmed);
    } catch (e) {
      lastSearchError =
          'Réponse BGG illisible. Vérifie bgg-proxy sur Supabase (JWT off + token BGG).';
      if (kDebugMode) debugPrint('BGG XML parse: $e');
      return null;
    }
  }

  static void _sortResults(
    List<Map<String, String>> items,
    String query,
    BggSearchSort sort,
    Map<String, _BggThingMeta> meta,
  ) {
    int rankOf(Map<String, String> g) => meta[g['id']]?.rank ?? 999_999;

    int yearOf(Map<String, String> g) =>
        int.tryParse(g['year'] ?? '') ?? 0;

    switch (sort) {
      case BggSearchSort.recent:
        items.sort((a, b) {
          final y = yearOf(b).compareTo(yearOf(a));
          if (y != 0) return y;
          return rankOf(a).compareTo(rankOf(b));
        });
      case BggSearchSort.popularity:
        items.sort((a, b) {
          final r = rankOf(a).compareTo(rankOf(b));
          if (r != 0) return r;
          return titleRelevanceScore(b['title']!, query)
              .compareTo(titleRelevanceScore(a['title']!, query));
        });
      case BggSearchSort.smart:
        sortByScore(
          items,
          (g) {
            final rel = titleRelevanceScore(g['title']!, query);
            final rank = rankOf(g);
            final popularityBonus = rank < 999_999
                ? (3000 - rank.clamp(0, 3000))
                : 0;
            return rel * 6 + popularityBonus;
          },
        );
    }
  }

  /// Jeux « hot » du moment sur BGG (tendances), mis en cache 30 min.
  static Future<List<Map<String, String>>> fetchHotBoardgames() async {
    if (!supportsWebSearch) return [];

    if (_useWebJsonApi) {
      if (_hotCache != null &&
          _hotCacheAt != null &&
          DateTime.now().difference(_hotCacheAt!) <
              const Duration(minutes: 30)) {
        return _hotCache!;
      }
      final data = await _jsonApiGet('hot', {});
      final games = _gamesFromJsonList(data?['games']);
      if (games.isEmpty) return [];
      final enriched = await enrichGameMaps(games);
      if (enriched.isNotEmpty) {
        _hotCache = enriched;
        _hotCacheAt = DateTime.now();
      }
      return enriched;
    }

    if (_hotCache != null &&
        _hotCacheAt != null &&
        DateTime.now().difference(_hotCacheAt!) <
            const Duration(minutes: 30)) {
      return _hotCache!;
    }

    try {
      final url = Uri.https('boardgamegeek.com', '/xmlapi2/hot', {
        'type': 'boardgame',
      });
      final response = await _getWithRetry(url);
      if (response.statusCode != 200 || response.body.isEmpty) return [];

      final document = XmlDocument.parse(response.body);
      var items = <Map<String, String>>[];

      for (final node in document.findAllElements('item')) {
        final id = node.getAttribute('id') ?? '';
        if (id.isEmpty) continue;
        final title = _primaryTitle(node);
        final year =
            node
                .findElements('yearpublished')
                .firstOrNull
                ?.getAttribute('value') ??
            '';
        final hotRank = node.getAttribute('rank') ?? '';
        final thumb =
            node.findElements('thumbnail').firstOrNull?.innerText ??
            node.getAttribute('thumbnail') ??
            '';

        items.add({
          'id': id,
          'title': title,
          'year': year,
          if (hotRank.isNotEmpty) 'hot_rank': hotRank,
          if (thumb.isNotEmpty) 'image_url': thumb,
        });
        if (items.length >= 50) break;
      }

      items = await enrichGameMaps(items);
      items.sort((a, b) {
        final ha = int.tryParse(a['hot_rank'] ?? '') ?? 999;
        final hb = int.tryParse(b['hot_rank'] ?? '') ?? 999;
        if (ha != hb) return ha.compareTo(hb);
        final ra = int.tryParse(a['bgg_rank'] ?? '') ?? 999999;
        final rb = int.tryParse(b['bgg_rank'] ?? '') ?? 999999;
        return ra.compareTo(rb);
      });

      _hotCache = items;
      _hotCacheAt = DateTime.now();
      return items;
    } catch (e) {
      if (kDebugMode) debugPrint('Erreur hot BGG: $e');
      return [];
    }
  }

  /// Fiche BGG par IDs (catalogue curé, genres).
  static Future<List<Map<String, String>>> fetchGamesByIds(
    List<String> ids,
  ) async {
    final unique = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return [];
    if (!supportsWebSearch) return [];

    if (_useWebJsonApi) {
      final out = <Map<String, String>>[];
      for (var i = 0; i < unique.length; i += _maxMetaLookup) {
        final chunk = unique.skip(i).take(_maxMetaLookup).join(',');
        final data = await _jsonApiGet('meta', {'ids': chunk});
        out.addAll(_gamesFromJsonList(data?['games']));
      }
      final enriched = await enrichGameMaps(out);
      final byId = <String, Map<String, String>>{
        for (final g in enriched)
          if ((g['id'] ?? '').isNotEmpty) g['id']!: g,
      };
      return _fillMissingImages(
        unique
            .map((id) => byId[id] ?? {'id': id, 'title': ''})
            .toList(),
      );
    }

    final meta = await _fetchThingMeta(unique);
    return _fillMissingImages(
      unique.map((id) {
      final m = meta[id];
      final imageUrl = (m?.image != null && m!.image!.isNotEmpty)
          ? m.image!
          : (m?.thumbnail ?? '');
      return {
        'id': id,
        'title': m?.title ?? '',
        if (m?.year != null && m!.year!.isNotEmpty) 'year': m.year!,
        if (m?.rank != null) 'bgg_rank': m!.rank.toString(),
        if (imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (m?.categories.isNotEmpty == true)
          'bgg_categories': m!.categories.join('|'),
        if (m?.avgRating != null) 'avg_rating': m!.avgRating!.toStringAsFixed(1),
      };
    }).where((g) => g['id']!.isNotEmpty).toList());
  }

  /// Complète les couvertures via fiche BGG si meta/hot n'en ont pas.
  static Future<List<Map<String, String>>> _fillMissingImages(
    List<Map<String, String>> games, {
    int maxLookups = 16,
  }) async {
    final missing = games
        .where(
          (g) => (g['image_url'] ?? '').isEmpty && (g['id'] ?? '').isNotEmpty,
        )
        .take(maxLookups)
        .toList();
    if (missing.isEmpty) return games;

    for (var i = 0; i < missing.length; i += 4) {
      final chunk = missing.skip(i).take(4);
      await Future.wait(
        chunk.map((g) async {
          final id = g['id']!;
          final details = await getGameFullDetails(id);
          final url = details?['image_url']?.toString();
          if (url != null && url.isNotEmpty) {
            g['image_url'] = url;
          }
        }),
      );
    }
    return games;
  }

  /// Rangs + miniatures (via API thing ; sur le web : proxy Supabase).
  static Future<Map<String, _BggThingMeta>> _fetchThingMeta(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};

    if (_useWebJsonApi) {
      final result = <String, _BggThingMeta>{};
      for (var i = 0; i < ids.length; i += _thingChunkSize) {
        final chunk = ids.skip(i).take(_thingChunkSize).toList();
        final data = await _jsonApiGet('meta', {'ids': chunk.join(',')});
        final list = _gamesFromJsonList(data?['games']);
        for (final g in list) {
          final id = g['id'] ?? '';
          if (id.isEmpty) continue;
          final rank = int.tryParse(g['bgg_rank'] ?? '');
          final thumb = g['image_url'];
          final thumbAlt = g['thumbnail_url'];
          final title = g['title'];
          final year = g['year'];
          final imageUrl = (thumb != null && thumb.isNotEmpty)
              ? thumb
              : (thumbAlt != null && thumbAlt.isNotEmpty ? thumbAlt : null);
          final cats = (g['bgg_categories'] ?? '')
              .split('|')
              .where((s) => s.isNotEmpty)
              .toList();
          final avg = double.tryParse(g['avg_rating'] ?? '');
          result[id] = _BggThingMeta(
            rank: rank,
            thumbnail: thumbAlt != null && thumbAlt.isNotEmpty ? thumbAlt : null,
            image: imageUrl,
            title: title != null && title.isNotEmpty ? title : null,
            year: year != null && year.isNotEmpty ? year : null,
            categories: cats,
            avgRating: avg,
          );
        }
      }
      return result;
    }

    final result = <String, _BggThingMeta>{};

    for (var i = 0; i < ids.length; i += _thingChunkSize) {
      final chunk = ids.skip(i).take(_thingChunkSize).toList();
      try {
        final url = Uri.https('boardgamegeek.com', '/xmlapi2/thing', {
          'id': chunk.join(','),
          'stats': '1',
        });
        final response = await _getWithRetry(url);
        if (response.statusCode != 200 || response.body.isEmpty) continue;

        final document = XmlDocument.parse(response.body);
        for (final item in document.findAllElements('item')) {
          final id = item.getAttribute('id');
          if (id == null) continue;

          final rankEl = item.findAllElements('rank').where(
            (r) => r.getAttribute('name') == 'boardgame',
          );
          final rawRank = rankEl.isNotEmpty
              ? rankEl.first.getAttribute('value')
              : null;
          int? rank;
          if (rawRank != null && rawRank != 'Not Ranked') {
            rank = int.tryParse(rawRank);
          }

          final fullImage =
              item.findAllElements('image').firstOrNull?.innerText;
          final thumb = item.findAllElements('thumbnail').firstOrNull?.innerText;
          final imageUrl = (fullImage != null && fullImage.isNotEmpty)
              ? fullImage
              : thumb;
          final year =
              item.findElements('yearpublished').firstOrNull?.getAttribute('value');
          final categories = item
              .findAllElements('link')
              .where((l) => l.getAttribute('type') == 'boardgamecategory')
              .map((l) => l.getAttribute('value'))
              .whereType<String>()
              .where((v) => v.isNotEmpty)
              .toList();
          final avgRaw = item
              .findAllElements('average')
              .firstOrNull
              ?.getAttribute('value');
          final avgRating = double.tryParse(avgRaw ?? '');

          result[id] = _BggThingMeta(
            rank: rank,
            image: imageUrl?.isNotEmpty == true ? imageUrl : null,
            thumbnail: thumb?.isNotEmpty == true ? thumb : null,
            title: _primaryTitle(item),
            year: year,
            categories: categories,
            avgRating: avgRating,
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('BGG thing (chunk) ignoré : $e');
        }
      }
    }

    return result;
  }

  /// Complète rang BGG + vignettes manquantes (web via bgg-api/meta).
  static Future<List<Map<String, String>>> enrichGameMaps(
    List<Map<String, String>> games,
  ) async {
    if (games.isEmpty) return games;

    final needMeta = games.where((g) {
      final id = g['id'] ?? '';
      if (id.isEmpty) return false;
      final noImg = (g['image_url'] ?? '').isEmpty;
      final noRank = (g['bgg_rank'] ?? '').isEmpty;
      final noTitle = (g['title'] ?? '').isEmpty;
      return noImg || noRank || noTitle;
    }).toList();

    if (needMeta.isEmpty) return games;

    final ids = needMeta.map((g) => g['id']!).toList();
    final meta = await _fetchThingMeta(ids);

    return games.map((g) {
      final m = meta[g['id']];
      if (m == null) return g;
      var imageUrl = g['image_url'] ?? '';
      if (imageUrl.isEmpty) {
        if (m.image != null && m.image!.isNotEmpty) {
          imageUrl = m.image!;
        } else if (m.thumbnail != null && m.thumbnail!.isNotEmpty) {
          imageUrl = m.thumbnail!;
        }
      }
      return {
        ...g,
        if ((g['title'] ?? '').isEmpty && m.title != null && m.title!.isNotEmpty)
          'title': m.title!,
        if ((g['year'] ?? '').isEmpty && m.year != null && m.year!.isNotEmpty)
          'year': m.year!,
        if ((g['bgg_rank'] ?? '').isEmpty && m.rank != null)
          'bgg_rank': m.rank.toString(),
        if (imageUrl.isNotEmpty) 'image_url': imageUrl,
        if ((g['bgg_categories'] ?? '').isEmpty && m.categories.isNotEmpty)
          'bgg_categories': m.categories.join('|'),
        if ((g['avg_rating'] ?? '').isEmpty && m.avgRating != null)
          'avg_rating': m.avgRating!.toStringAsFixed(1),
      };
    }).toList();
  }

  static Map<String, dynamic>? _parseThingItem(XmlElement item) {
    final image =
        item.findAllElements('image').firstOrNull?.innerText ??
        item.findAllElements('thumbnail').firstOrNull?.innerText;

    int? parseAttr(String tag) {
      final raw =
          item.findElements(tag).firstOrNull?.getAttribute('value') ?? '';
      return int.tryParse(raw);
    }

    final bggId = item.getAttribute('id');
    final year = parseAttr('yearpublished');
    final minAge = parseAttr('minage');
    final playingTime = parseAttr('playingtime') ??
        parseAttr('maxplaytime') ??
        parseAttr('minplaytime');

    final categories = item
        .findAllElements('link')
        .where((l) => l.getAttribute('type') == 'boardgamecategory')
        .map((l) => l.getAttribute('value'))
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .toList();

    final itemType = item.getAttribute('type');
    final isExpansion = itemType == 'boardgameexpansion';

    String? baseBggId;
    String? baseTitle;
    if (isExpansion) {
      for (final link in item.findAllElements('link')) {
        if (link.getAttribute('type') != 'boardgameexpansion') continue;
        if (link.getAttribute('inbound') != 'true') continue;
        final linkId = link.getAttribute('id');
        final linkTitle = link.getAttribute('value');
        if (linkId != null && linkId.isNotEmpty) {
          baseBggId = linkId;
          baseTitle = linkTitle;
          break;
        }
      }
    }

    final desc = _stripHtml(
      item.findElements('description').firstOrNull?.innerText,
    );
    final bestPlayers = _parseBestPlayerCount(item);
    final avgRaw =
        item.findAllElements('average').firstOrNull?.getAttribute('value');
    final avgRating = double.tryParse(avgRaw ?? '');

    return {
      'bgg_id': ?bggId,
      if (image != null && image.isNotEmpty) 'image_url': image,
      'year_published': ?year,
      'min_age': ?minAge,
      'min_players': parseAttr('minplayers'),
      'max_players': parseAttr('maxplayers'),
      'playing_time': _positivePlayingTime(playingTime),
      if (categories.isNotEmpty) 'bgg_categories': categories,
      if (desc.isNotEmpty) 'bgg_description': desc,
      if (avgRating != null && avgRating > 0) 'bgg_avg_rating': avgRating,
      'bgg_best_players': ?bestPlayers,
      if (isExpansion) 'bgg_is_expansion': true,
      'base_game_bgg_id': ?baseBggId,
      if (baseTitle != null && baseTitle.isNotEmpty)
        'base_game_title': baseTitle,
    };
  }

  /// Fiche BGG du jeu (règles, fichiers, forum).
  static String? gamePageUrl(String? bggId) {
    if (bggId == null || bggId.isEmpty) return null;
    return 'https://boardgamegeek.com/boardgame/$bggId';
  }

  static String? expansionPageUrl(String? bggId) {
    if (bggId == null || bggId.isEmpty) return null;
    return 'https://boardgamegeek.com/boardgameexpansion/$bggId';
  }

  /// Accroche BGG officielle (`short_description` sur le site).
  static Future<String?> fetchThingDescription(String bggId) async {
    if (bggId.isEmpty) return null;
    final details = await getGameFullDetails(bggId);
    final short = details?['bgg_short_description']?.toString().trim();
    if (short != null && short.isNotEmpty) return short;
    return null;
  }

  /// `short_description` BGG (API interne geekitems, absente du XML API2).
  static Future<Map<String, dynamic>> _fetchGeekItemExtras(String bggId) async {
    if (bggId.isEmpty) return {};
    try {
      final uri = Uri.https('boardgamegeek.com', '/api/geekitems', {
        'objectid': bggId,
        'objecttype': 'thing',
      });
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'CollectionFamille/1.0',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode != 200 || response.body.isEmpty) return {};
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return {};
      final item = decoded['item'];
      if (item is! Map) return {};
      final short = item['short_description']?.toString().trim();
      if (short == null || short.isEmpty) return {};
      return {'bgg_short_description': short};
    } catch (e) {
      if (kDebugMode) debugPrint('BGG geekitems $bggId: $e');
      return {};
    }
  }

  static int? _parseBestPlayerCount(XmlElement item) {
    XmlElement? poll;
    for (final p in item.findAllElements('poll')) {
      if (p.getAttribute('name') == 'suggested_numplayers') {
        poll = p;
        break;
      }
    }
    if (poll == null) return null;

    int? bestCount;
    var maxVotes = 0;
    for (final results in poll.findElements('results')) {
      final numPlayers = _parsePollNumPlayers(
        results.getAttribute('numplayers'),
      );
      if (numPlayers == null) continue;

      for (final result in results.findElements('result')) {
        if (result.getAttribute('value') != 'Best') continue;
        final votes =
            int.tryParse(result.getAttribute('numvotes') ?? '') ?? 0;
        if (votes > maxVotes) {
          maxVotes = votes;
          bestCount = numPlayers;
        }
      }
    }
    return maxVotes > 0 ? bestCount : null;
  }

  static int? _parsePollNumPlayers(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'^(\d+)').firstMatch(raw.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  @Deprecated('Use gamePageUrl')
  static String? rulesFilesUrl(String? bggId) => gamePageUrl(bggId);

  static String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _expansionSummary(XmlElement item) {
    final desc = item.findElements('description').firstOrNull?.innerText;
    final clean = _stripHtml(desc);
    if (clean.isEmpty) return null;
    return clean.length > 140 ? '${clean.substring(0, 137)}…' : clean;
  }

  static int _compareExpansionsByPopularity(BggExpansion a, BggExpansion b) {
    final ra = a.bggRank;
    final rb = b.bggRank;
    if (ra != null && rb != null) return ra.compareTo(rb);
    if (ra != null) return -1;
    if (rb != null) return 1;
    final ya = a.year ?? 0;
    final yb = b.year ?? 0;
    if (ya != yb) return yb.compareTo(ya);
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  /// Extensions BGG du jeu de base (`inbound="true"` sur le lien expansion).
  static Future<List<BggExpansion>> fetchExpansions(String baseGameBggId) async {
    if (baseGameBggId.isEmpty) return [];
    if (_useWebJsonApi) {
      if (!_webProxyReady) return [];
      final data = await _jsonApiGet('expansions', {'id': baseGameBggId});
      final raw = data?['expansions'];
      if (raw is! List) return [];
      return raw.whereType<Map>().map((e) {
        return BggExpansion(
          bggId: e['bggId']?.toString() ?? '',
          title: e['title']?.toString() ?? '',
          imageUrl: e['imageUrl']?.toString(),
          year: e['year'] is int ? e['year'] as int : int.tryParse('${e['year']}'),
          summary: e['summary']?.toString(),
          bggRank: e['bggRank'] is int
              ? e['bggRank'] as int
              : int.tryParse('${e['bggRank']}'),
          avgRating: e['avgRating'] is num
              ? (e['avgRating'] as num).toDouble()
              : double.tryParse('${e['avgRating']}'),
        );
      }).where((e) => e.bggId.isNotEmpty).toList();
    }

    try {
      final url = Uri.https('boardgamegeek.com', '/xmlapi2/thing', {
        'id': baseGameBggId,
      });
      final response = await _getWithRetry(url);
      if (response.statusCode != 200 || response.body.isEmpty) return [];

      final document = XmlDocument.parse(response.body);
      final baseItem = document.findAllElements('item').firstOrNull;
      if (baseItem == null) return [];

      final expansionIds = <String, String>{};
      for (final link in baseItem.findAllElements('link')) {
        final type = link.getAttribute('type');
        if (type != 'boardgameexpansion' && type != 'boardgameintegration') {
          continue;
        }
        final inbound = link.getAttribute('inbound');
        if (inbound == 'false') continue;
        final id = link.getAttribute('id');
        final title = link.getAttribute('value');
        if (id != null && id.isNotEmpty && title != null && title.isNotEmpty) {
          expansionIds[id] = title;
        }
      }
      if (expansionIds.isEmpty) return [];

      final expansions = <BggExpansion>[];
      final ids = expansionIds.keys.toList();

      for (var i = 0; i < ids.length; i += _thingChunkSize) {
        final chunk = ids.skip(i).take(_thingChunkSize).toList();
        final detailUrl = Uri.https('boardgamegeek.com', '/xmlapi2/thing', {
          'id': chunk.join(','),
          'stats': '1',
        });
        final detailRes = await _getWithRetry(detailUrl);
        if (detailRes.statusCode != 200 || detailRes.body.isEmpty) continue;

        final detailDoc = XmlDocument.parse(detailRes.body);
        for (final item in detailDoc.findAllElements('item')) {
          final id = item.getAttribute('id');
          if (id == null) continue;

          final image =
              item.findAllElements('image').firstOrNull?.innerText ??
              item.findAllElements('thumbnail').firstOrNull?.innerText;
          final yearRaw =
              item.findElements('yearpublished').firstOrNull?.getAttribute('value');
          final year = int.tryParse(yearRaw ?? '');

          final rankEl = item.findAllElements('rank').where(
            (r) => r.getAttribute('name') == 'boardgame',
          );
          final rawRank = rankEl.isNotEmpty
              ? rankEl.first.getAttribute('value')
              : null;
          int? rank;
          if (rawRank != null && rawRank != 'Not Ranked') {
            rank = int.tryParse(rawRank);
          }

          final avgRaw =
              item.findAllElements('average').firstOrNull?.getAttribute('value');
          final avgRating = double.tryParse(avgRaw ?? '');

          expansions.add(
            BggExpansion(
              bggId: id,
              title: _primaryTitle(item),
              imageUrl: image?.isNotEmpty == true ? image : null,
              year: year,
              summary: _expansionSummary(item),
              bggRank: rank,
              avgRating:
                  avgRating != null && avgRating > 0 ? avgRating : null,
            ),
          );
        }
      }

      expansions.sort(_compareExpansionsByPopularity);
      return expansions;
    } catch (e) {
      if (kDebugMode) debugPrint('BGG expansions $baseGameBggId: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getGameFullDetails(String bggId) async {
    if (_useWebJsonApi) {
      if (!_webProxyReady) return null;
      final data = await _jsonApiGet('game', {'id': bggId});
      final game = data?['game'];
      return game is Map<String, dynamic> ? game : null;
    }

    try {
      final results = await Future.wait<Object?>([
        _fetchThingXmlDetails(bggId),
        _fetchGeekItemExtras(bggId),
      ]);
      final thing = results[0] as Map<String, dynamic>?;
      final extras = results[1] as Map<String, dynamic>? ?? {};
      if (thing == null && extras.isEmpty) return null;
      return {...?thing, ...extras};
    } catch (e) {
      if (kDebugMode) debugPrint('Erreur détails BGG: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchThingXmlDetails(String bggId) async {
    final url = Uri.https('boardgamegeek.com', '/xmlapi2/thing', {
      'id': bggId,
      'stats': '1',
    });
    final response = await _getWithRetry(url);

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      final document = XmlDocument.parse(response.body);
      final item = document.findAllElements('item').firstOrNull;
      if (item != null) return _parseThingItem(item);
    }
    return null;
  }

  static int? _positivePlayingTime(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    final parsed = int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
