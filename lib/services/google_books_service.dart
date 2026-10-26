import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_env.dart';
import '../utils/book_vf_edition.dart';
import '../utils/web_catalog_proxy.dart';
import 'open_library_service.dart';

/// Google Books API — source prioritaire VF (`langRestrict=fr`).
/// Sur 429/403 avec clé : retry **sans** `&key=`, puis via `catalog-proxy`.
/// Cache mémoire + SharedPreferences (TTL 24h) par requête `q`.
class GoogleBooksService {
  static String? get _apiKey => AppEnv.googleBooksApiKey;

  static bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  /// Après un 429/403 sur la clé, on saute `&key=` pour le reste de la session.
  static bool _preferKeyless = false;

  static final Map<String, _CacheEntry> _memCache = {};
  static const _prefsPrefix = 'gb_cache_v1:';
  static const _ttl = Duration(hours: 24);

  static Uri _volumesUri(Map<String, String> query, {required bool withKey}) {
    final params = Map<String, String>.from(query);
    if (withKey) {
      final key = _apiKey;
      if (key != null && key.isNotEmpty) params['key'] = key;
    }
    return Uri.https('www.googleapis.com', '/books/v1/volumes', params);
  }

  static String _cacheKey(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    return keys.map((k) => '$k=${params[k]}').join('&');
  }

  static Future<List<Map<String, String>>?> _readCache(String key) async {
    final mem = _memCache[key];
    if (mem != null && !mem.isExpired) return mem.hits;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final ts = decoded['ts'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts > _ttl.inMilliseconds) {
        await prefs.remove('$_prefsPrefix$key');
        return null;
      }
      final list = decoded['hits'] as List<dynamic>? ?? const [];
      final hits = list
          .map((e) => Map<String, String>.from(
                (e as Map).map((k, v) => MapEntry('$k', '$v')),
              ))
          .toList();
      _memCache[key] = _CacheEntry(hits, DateTime.fromMillisecondsSinceEpoch(ts));
      return hits;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(
    String key,
    List<Map<String, String>> hits,
  ) async {
    final now = DateTime.now();
    _memCache[key] = _CacheEntry(hits, now);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefsPrefix$key',
        jsonEncode({
          'ts': now.millisecondsSinceEpoch,
          'hits': hits,
        }),
      );
    } catch (_) {}
  }

  /// GET volumes : clé → sans clé → catalog-proxy.
  static Future<http.Response?> _fetchVolumes(Map<String, String> params) async {
    Future<http.Response> get(Uri uri) =>
        http.get(uri).timeout(const Duration(seconds: 15));

    // 1) Avec clé (si dispo et pas encore brûlée).
    if (!_preferKeyless && hasApiKey) {
      try {
        final res = await get(_volumesUri(params, withKey: true));
        if (res.statusCode == 200) return res;
        if (res.statusCode == 429 || res.statusCode == 403) {
          _preferKeyless = true;
          if (kDebugMode) {
            debugPrint(
              'Google Books ${res.statusCode} avec clé → retry sans key',
            );
          }
        } else {
          return res;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Google Books keyed: $e');
      }
    }

    // 2) Sans clé (quota anonyme / IP).
    try {
      final res = await get(_volumesUri(params, withKey: false));
      if (res.statusCode == 200) return res;
      if (res.statusCode == 429 || res.statusCode == 403) {
        if (kDebugMode) {
          debugPrint('Google Books ${res.statusCode} keyless → catalog-proxy');
        }
      } else {
        return res;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Google Books keyless: $e');
    }

    // 3) Edge proxy (CORS + contournement navigateur).
    try {
      final target = _volumesUri(params, withKey: false);
      final proxied = proxiedCatalogUri(target);
      // Force proxy même hors web pour le retry serveur.
      final uri = kIsWeb
          ? proxied
          : Uri.parse(
              '${AppEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
              '/functions/v1/catalog-proxy'
              '?url=${Uri.encodeComponent(target.toString())}'
              '&apikey=${Uri.encodeComponent(AppEnv.supabaseAnonKey)}',
            );
      final res = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'apikey': AppEnv.supabaseAnonKey,
              'Authorization': 'Bearer ${AppEnv.supabaseAnonKey}',
            },
          )
          .timeout(const Duration(seconds: 20));
      return res;
    } catch (e) {
      if (kDebugMode) debugPrint('Google Books proxy: $e');
      return null;
    }
  }

  static List<Map<String, String>> _parseItems(
    String body, {
    String isbnFallback = '',
  }) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      final out = <Map<String, String>>[];
      for (final raw in items) {
        final mapped = _mapVolume(raw as Map<String, dynamic>, isbnFallback);
        if (mapped == null) continue;
        if (!BookVfEdition.isFrenchEdition(
          title: mapped['title'] ?? '',
          language: mapped['language'],
          source: mapped['source'],
        )) {
          continue;
        }
        out.add(mapped);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Résultat normalisé (même forme qu'Open Library + champs série).
  static Future<Map<String, String>?> lookupByIsbn(String isbn) async {
    for (final variant in OpenLibraryService.isbnLookupVariants(isbn)) {
      try {
        final params = {'q': 'isbn:$variant', 'maxResults': '3'};
        final key = _cacheKey(params);
        final cached = await _readCache(key);
        if (cached != null && cached.isNotEmpty) return cached.first;

        final response = await _fetchVolumes(params);
        if (response == null || response.statusCode != 200) continue;
        final hits = _parseItems(response.body, isbnFallback: variant);
        await _writeCache(key, hits);
        if (hits.isNotEmpty) return hits.first;
      } catch (e) {
        if (kDebugMode) debugPrint('Google Books ISBN: $e');
      }
    }
    return null;
  }

  static Future<List<Map<String, String>>> search(
    String query, {
    int maxResults = 20,
    int startIndex = 0,
    String? langRestrict = 'fr',
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final params = <String, String>{
        'q': q,
        'maxResults': '${maxResults.clamp(1, 40)}',
        'startIndex': '${startIndex.clamp(0, 200)}',
        'orderBy': 'relevance',
      };
      if (langRestrict != null && langRestrict.isNotEmpty) {
        params['langRestrict'] = langRestrict;
      }
      final key = _cacheKey(params);
      final cached = await _readCache(key);
      if (cached != null) return cached;

      final response = await _fetchVolumes(params);
      if (response == null || response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            'Google Books search ${response?.statusCode ?? 'null'} — []',
          );
        }
        return [];
      }
      final hits = _parseItems(response.body);
      await _writeCache(key, hits);
      return hits;
    } catch (e) {
      if (kDebugMode) debugPrint('Google Books search: $e');
      return [];
    }
  }

  /// 1–3 pages séquentielles (jamais en parallèle) pour une série entière.
  static Future<List<Map<String, String>>> searchSeriesBatched(
    String seriesTitle, {
    String? author,
    int maxPages = 3,
    Duration pageDelay = const Duration(milliseconds: 600),
    String? langRestrict = 'fr',
  }) async {
    final name = seriesTitle.trim();
    if (name.length < 2) return [];
    final q = author != null && author.trim().isNotEmpty
        ? 'intitle:"$name" inauthor:"${author.trim()}"'
        : 'intitle:"$name"';
    final out = <Map<String, String>>[];
    final seen = <String>{};
    final pages = maxPages.clamp(1, 3);
    for (var page = 0; page < pages; page++) {
      if (page > 0) await Future<void>.delayed(pageDelay);
      final batch = await search(
        q,
        maxResults: 40,
        startIndex: page * 40,
        langRestrict: langRestrict,
      );
      if (batch.isEmpty) break;
      for (final hit in batch) {
        final title = hit['title']?.trim().toLowerCase() ?? '';
        if (title.isEmpty || !seen.add(title)) continue;
        out.add(hit);
      }
      if (batch.length < 40) break;
    }
    return out;
  }

  static Map<String, String>? _mapVolume(
    Map<String, dynamic> item,
    String isbnFallback,
  ) {
    final info = item['volumeInfo'] as Map<String, dynamic>?;
    if (info == null) return null;

    final title = info['title'] as String?;
    if (title == null || title.isEmpty) return null;
    // Rejet strict éditions US « Vol. N ».
    if (BookVfEdition.isUsVolTitle(title)) return null;
    final subtitle = info['subtitle'] as String?;
    if (subtitle != null && BookVfEdition.isUsVolTitle(subtitle)) return null;

    final langRaw = info['language'];
    final language = langRaw is List
        ? langRaw.map((e) => e.toString()).join(',')
        : langRaw?.toString();
    if (language != null &&
        language.isNotEmpty &&
        !BookVfEdition.isFrenchLanguage(language)) {
      return null;
    }

    final authors = (info['authors'] as List<dynamic>?)
        ?.map((a) => a.toString())
        .toList();
    final author = authors?.isNotEmpty == true ? authors!.first : '';

    final published = info['publishedDate'] as String? ?? '';
    final year = published.length >= 4 ? published.substring(0, 4) : published;

    final links = info['imageLinks'] as Map<String, dynamic>?;
    final rawImage =
        (links?['extraLarge'] ??
                links?['large'] ??
                links?['medium'] ??
                links?['thumbnail'] ??
                links?['smallThumbnail'])
            ?.toString() ??
            '';
    final imageHttps = _hdGoogleCover(rawImage);

    String? isbn = isbnFallback;
    final ids = info['industryIdentifiers'] as List<dynamic>? ?? [];
    for (final raw in ids) {
      final id = raw as Map<String, dynamic>;
      final type = id['type'] as String? ?? '';
      final value = id['identifier']?.toString();
      if (value == null || value.isEmpty) continue;
      if (type == 'ISBN_13' || type == 'ISBN_10') {
        isbn = value;
        break;
      }
    }

    final result = <String, String>{
      'title': title,
      'author': author,
      'year': year,
      'image_url': imageHttps,
      'source': 'google_books',
      'google_books_id': item['id']?.toString() ?? '',
      if (published.isNotEmpty) 'published_date': published,
      if (isbn != null && isbn.isNotEmpty) 'isbn': isbn,
      if (language != null && language.isNotEmpty) 'language': language,
    };

    if (subtitle != null && subtitle.isNotEmpty) {
      result['subtitle'] = subtitle;
    }

    final publisher = info['publisher'] as String?;
    if (publisher != null && publisher.isNotEmpty) {
      result['publisher'] = publisher;
    }

    final avgRating = info['averageRating'];
    if (avgRating is num && avgRating > 0) {
      result['community_rating'] =
          avgRating.toDouble().clamp(0, 5).toStringAsFixed(2);
    }

    final seriesInfo = info['seriesInfo'] as Map<String, dynamic>?;
    if (seriesInfo != null) {
      final displayNum = seriesInfo['bookDisplayNumber']?.toString();
      if (displayNum != null && displayNum.isNotEmpty) {
        result['series_volume'] = displayNum;
      }
      final volumes = seriesInfo['volumeSeries'] as List<dynamic>?;
      if (volumes != null && volumes.isNotEmpty) {
        final first = volumes.first as Map<String, dynamic>;
        final order = first['orderNumber'];
        if (order != null) result['series_volume'] = order.toString();
      }
    }

    final parsed = _parseSeriesFromTitle(title);
    if (parsed != null) {
      result.putIfAbsent('series_title', () => parsed.$1);
      result.putIfAbsent('series_volume', () => parsed.$2);
    }

    return result;
  }

  static (String, String)? _parseSeriesFromTitle(String title) {
    final patterns = [
      RegExp(
        r'^(.+?)\s*[,:\-–]\s*(?:tome|vol\.?|volume|#)\s*(\d+)',
        caseSensitive: false,
      ),
      RegExp(r'^(.+?)\s+\((\d+)\)$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(title.trim());
      if (m != null) {
        return (m.group(1)!.trim(), m.group(2)!);
      }
    }
    return null;
  }

  static String _hdGoogleCover(String url) {
    if (url.isEmpty) return '';
    var out = url.replaceFirst('http://', 'https://');
    out = out.replaceAll('&edge=curl', '');
    out = out.replaceAll(RegExp(r'[&?]edge=curl'), '');
    if (out.contains('zoom=')) {
      out = out.replaceAll(RegExp(r'zoom=\d'), 'zoom=2');
    } else if (out.contains('books.google.com') ||
        out.contains('googleusercontent.com')) {
      out = out.contains('?') ? '$out&zoom=2' : '$out?zoom=2';
    }
    return out;
  }
}

class _CacheEntry {
  final List<Map<String, String>> hits;
  final DateTime at;
  _CacheEntry(this.hits, this.at);
  bool get isExpired =>
      DateTime.now().difference(at) > const Duration(hours: 24);
}
