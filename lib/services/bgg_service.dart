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
  static const _maxMetaLookup = 50;
  static const _thingChunkSize = 8;
  static const _maxPollAttempts = 10;

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

  /// L'API XML BGG répond souvent 202 (« Please try again ») : on réessaie.
  static Future<http.Response> _getWithRetry(Uri url) async {
    if (_useWebJsonApi) {
      return http.Response('', 503);
    }

    final target = url;
    final headers = _headers;

    http.Response? last;
    for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
      last = await http.get(target, headers: headers);
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
    if (!supportsWebSearch) {
      lastSearchError =
          'Recherche BGG indisponible : configure Supabase (fonction bgg-api).';
      return [];
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
      if (data == null) return [];
      return enrichGameMaps(_gamesFromJsonList(data['games']));
    }

    try {
      final url = Uri.https('boardgamegeek.com', '/xmlapi2/search', {
        'query': trimmed,
        'type': 'boardgame',
      });
      final response = await _getWithRetry(url);

      if (response.statusCode != 200 || response.body.isEmpty) {
        lastSearchError = response.statusCode == 0
            ? 'Réseau bloqué (CORS ou connexion). Vérifie le proxy bgg-proxy sur Supabase (JWT désactivé).'
            : 'BGG a répondu ${response.statusCode}';
        return [];
      }

      final document = _parseXmlDocument(response.body);
      if (document == null) return [];
      final items = document.findAllElements('item');

      final candidates = <Map<String, String>>[];
      for (final node in items) {
        if (candidates.length >= _maxSearchResults) break;
        final id = node.getAttribute('id') ?? '';
        if (id.isEmpty) continue;
        final year =
            node
                .findElements('yearpublished')
                .firstOrNull
                ?.getAttribute('value') ??
            '';
        candidates.add({
          'id': id,
          'title': _primaryTitle(node),
          'year': year,
        });
      }

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

      return ranked.take(40).toList();
    } catch (e) {
      lastSearchError = 'Recherche BGG impossible : $e';
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

    return {
      if (bggId != null) 'bgg_id': bggId,
      if (image != null && image.isNotEmpty) 'image_url': image,
      if (year != null) 'year_published': year,
      if (minAge != null) 'min_age': minAge,
      'min_players': parseAttr('minplayers'),
      'max_players': parseAttr('maxplayers'),
      'playing_time': _positivePlayingTime(playingTime),
      if (categories.isNotEmpty) 'bgg_categories': categories,
    };
  }

  /// Fiche BGG du jeu (règles, fichiers, forum).
  static String? gamePageUrl(String? bggId) {
    if (bggId == null || bggId.isEmpty) return null;
    return 'https://boardgamegeek.com/boardgame/$bggId';
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

          expansions.add(
            BggExpansion(
              bggId: id,
              title: _primaryTitle(item),
              imageUrl: image?.isNotEmpty == true ? image : null,
              year: year,
              summary: _expansionSummary(item),
              bggRank: rank,
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
      final url = Uri.https('boardgamegeek.com', '/xmlapi2/thing', {
        'id': bggId,
      });
      final response = await _getWithRetry(url);

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final document = XmlDocument.parse(response.body);
        final item = document.findAllElements('item').firstOrNull;
        if (item != null) return _parseThingItem(item);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erreur détails BGG: $e');
    }
    return null;
  }

  static int? _positivePlayingTime(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    final parsed = int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
