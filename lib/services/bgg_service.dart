import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

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

  /// Sur Flutter Web, l'API « thing » BGG est bloquée par CORS (Failed to fetch).
  static bool get _canUseThingApi => !kIsWeb;

  static List<Map<String, String>>? _hotCache;
  static DateTime? _hotCacheAt;

  static Map<String, String> get _headers {
    final token = dotenv.env['BGG_APPLICATION_TOKEN'];
    if (token == null || token.isEmpty) {
      throw Exception('Variable BGG_APPLICATION_TOKEN manquante dans .env');
    }
    return {
      'User-Agent': 'Mozilla/5.0 (Android 14; SM-S931B) AppleWebKit/537.36',
      'Accept': 'application/xml',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<List<Map<String, String>>> searchGames(
    String query, {
    BggSearchSort sort = BggSearchSort.smart,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final url = Uri.https('boardgamegeek.com', '/xmlapi2/search', {
        'query': trimmed,
        'type': 'boardgame',
      });
      final response = await http.get(url, headers: _headers);

      if (response.statusCode != 200) return [];

      final document = XmlDocument.parse(response.body);
      final items = document.findAllElements('item');

      final candidates = <Map<String, String>>[];
      for (final node in items) {
        if (candidates.length >= _maxSearchResults) break;
        final title =
            node.findElements('name').first.getAttribute('value') ??
            'Sans titre';
        final id = node.getAttribute('id') ?? '';
        if (id.isEmpty) continue;
        final year =
            node
                .findElements('yearpublished')
                .firstOrNull
                ?.getAttribute('value') ??
            '';
        candidates.add({'id': id, 'title': title, 'year': year});
      }

      if (candidates.isEmpty) return [];

      sortByScore(
        candidates,
        (g) => titleRelevanceScore(g['title']!, trimmed),
      );

      final top = candidates.take(_maxMetaLookup).toList();
      final meta = await _fetchThingMeta(top.map((g) => g['id']!).toList());

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
      final response = await http.get(url, headers: _headers);
      if (response.statusCode != 200) return [];

      final document = XmlDocument.parse(response.body);
      final items = <Map<String, String>>[];

      for (final node in document.findAllElements('item')) {
        final id = node.getAttribute('id') ?? '';
        if (id.isEmpty) continue;
        final title =
            node.findElements('name').firstOrNull?.getAttribute('value') ??
            'Sans titre';
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

  /// Rangs + miniatures (mobile/desktop). Sur le web : ignoré (CORS).
  static Future<Map<String, _BggThingMeta>> _fetchThingMeta(
    List<String> ids,
  ) async {
    if (ids.isEmpty || !_canUseThingApi) return {};

    final result = <String, _BggThingMeta>{};

    for (var i = 0; i < ids.length; i += _thingChunkSize) {
      final chunk = ids.skip(i).take(_thingChunkSize).toList();
      try {
        final url = Uri.https('boardgamegeek.com', '/xmlapi2/thing', {
          'id': chunk.join(','),
          'stats': '1',
        });
        final response = await http.get(url, headers: _headers);
        if (response.statusCode != 200) continue;

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

  static Future<Map<String, dynamic>?> getGameFullDetails(String bggId) async {
    if (!_canUseThingApi) {
      // Web : pas d'appel thing ; l'objet sera enregistré sans image BGG auto.
      return null;
    }

    try {
      final url = Uri.https('boardgamegeek.com', '/xmlapi2/thing', {
        'id': bggId,
      });
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final item = document.findAllElements('item').first;

        return {
          'image_url':
              item.findAllElements('image').firstOrNull?.innerText ??
              item.findAllElements('thumbnail').firstOrNull?.innerText,
          'min_players': int.tryParse(
            item
                    .findElements('minplayers')
                    .firstOrNull
                    ?.getAttribute('value') ??
                '',
          ),
          'max_players': int.tryParse(
            item
                    .findElements('maxplayers')
                    .firstOrNull
                    ?.getAttribute('value') ??
                '',
          ),
          'playing_time': int.tryParse(
            item
                    .findElements('playingtime')
                    .firstOrNull
                    ?.getAttribute('value') ??
                '',
          ),
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erreur détails BGG: $e');
    }
    return null;
  }
}
