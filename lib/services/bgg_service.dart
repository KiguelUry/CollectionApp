import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:functions_client/functions_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import '../config/app_env.dart';
import '../models/bgg_expansion.dart';
import '../utils/search_relevance.dart';

enum BggSearchSort {
  /// Pertinence du titre + popularité BGG (classement).
  smart,

  /// Année de sortie la plus récente.
  recent,
}

class _BggThingMeta {
  final int? rank;
  final String? thumbnail;

  const _BggThingMeta({this.rank, this.thumbnail});
}

class BggService {
  static const _maxSearchResults = 40;
  static const _maxMetaLookup = 15;
  static const _thingChunkSize = 8;
  static const _maxPollAttempts = 10;

  /// Sur le web, les appels passent par la Edge Function Supabase `bgg-proxy`.
  static bool get _useWebProxy => kIsWeb;

  static bool get _webProxyReady {
    return AppEnv.supabaseUrl.isNotEmpty && AppEnv.supabaseAnonKey.isNotEmpty;
  }

  static bool get webBggAvailable => !_useWebProxy || _webProxyReady;

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

  static Uri _requestUri(Uri bggUri) {
    if (!_useWebProxy) return bggUri;
    final base = AppEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/functions/v1/bgg-proxy').replace(
      queryParameters: {
        'path': bggUri.path,
        ...bggUri.queryParameters,
      },
    );
  }

  static Map<String, String> _requestHeaders() {
    final headers = Map<String, String>.from(_headers);
    if (_useWebProxy && _webProxyReady) {
      final anon = AppEnv.supabaseAnonKey;
      headers['apikey'] = anon;
      headers['Authorization'] = 'Bearer $anon';
    }
    return headers;
  }

  /// Sur le web, passe par `functions.invoke` (auth Supabase + CORS fiables).
  static Future<http.Response> _getViaSupabaseProxy(Uri bggUri) async {
    final client = Supabase.instance.client;
    http.Response? last;

    for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
      try {
        final res = await client.functions.invoke(
          'bgg-proxy',
          method: HttpMethod.get,
          queryParameters: {
            'path': bggUri.path,
            ...bggUri.queryParameters,
          },
        );
        final body = res.data is String
            ? res.data as String
            : (res.data?.toString() ?? '');
        last = http.Response(body, res.status);
      } on FunctionException catch (e) {
        final details = e.details?.toString() ?? e.reasonPhrase ?? '';
        last = http.Response(details, e.status);
      } catch (e) {
        if (kDebugMode) debugPrint('bgg-proxy invoke: $e');
        return http.Response(e.toString(), 0);
      }

      final pending = last.statusCode == 202 ||
          (last.statusCode == 200 && last.body.contains('Please try again'));
      if (!pending) return last;
      await Future.delayed(Duration(milliseconds: 400 + attempt * 250));
    }
    return last!;
  }

  /// L'API XML BGG répond souvent 202 (« Please try again ») : on réessaie.
  static Future<http.Response> _getWithRetry(Uri url) async {
    if (_useWebProxy && !_webProxyReady) {
      return http.Response('', 503);
    }

    if (_useWebProxy) {
      return _getViaSupabaseProxy(url);
    }

    final target = _requestUri(url);
    final headers = _requestHeaders();

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
    try {
      final url = Uri.https('boardgamegeek.com', '/xmlapi2/search', {
        'query': trimmed,
        'type': 'boardgame',
      });
      final response = await _getWithRetry(url);

      if (response.statusCode != 200 || response.body.isEmpty) {
        lastSearchError = response.statusCode == 0
            ? 'Réseau bloqué (CORS ou connexion). Vérifie le proxy bgg-proxy sur Supabase.'
            : 'BGG a répondu ${response.statusCode}';
        return [];
      }

      final document = XmlDocument.parse(response.body);
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

      return ranked.take(20).toList();
    } catch (e) {
      lastSearchError = e.toString();
      if (kDebugMode) debugPrint('Erreur recherche BGG: $e');
    }
    return [];
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
      case BggSearchSort.smart:
        sortByScore(
          items,
          (g) {
            final rel = titleRelevanceScore(g['title']!, query);
            final rank = rankOf(g);
            final popularityBonus = rank < 999_999
                ? (2000 - rank.clamp(0, 2000))
                : 0;
            return rel * 10 + popularityBonus;
          },
        );
    }
  }

  /// Jeux « hot » du moment sur BGG (tendances), mis en cache 30 min.
  static Future<List<Map<String, String>>> fetchHotBoardgames() async {
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
      final items = <Map<String, String>>[];

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
        if (items.length >= 20) break;
      }

      _hotCache = items;
      _hotCacheAt = DateTime.now();
      return items;
    } catch (e) {
      if (kDebugMode) debugPrint('Erreur hot BGG: $e');
      return [];
    }
  }

  /// Rangs + miniatures (via API thing ; sur le web : proxy Supabase).
  static Future<Map<String, _BggThingMeta>> _fetchThingMeta(
    List<String> ids,
  ) async {
    if (ids.isEmpty || (_useWebProxy && !_webProxyReady)) return {};

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

          final thumb =
              item.findAllElements('thumbnail').firstOrNull?.innerText ??
              item.findAllElements('image').firstOrNull?.innerText;

          result[id] = _BggThingMeta(
            rank: rank,
            thumbnail: thumb?.isNotEmpty == true ? thumb : null,
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
      'playing_time': playingTime,
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
    if (baseGameBggId.isEmpty || (_useWebProxy && !_webProxyReady)) {
      return [];
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
    if (_useWebProxy && !_webProxyReady) return null;

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
}
