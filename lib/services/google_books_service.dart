import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_env.dart';
import '../utils/book_title_parser.dart';
import '../utils/book_vf_edition.dart';
import '../utils/web_catalog_proxy.dart';
import 'open_library_service.dart';

/// Google Books API — source prioritaire VF (`langRestrict=fr`).
/// Pas de `orderBy` (provoque des 503). Clé conservée sur retry 503.
/// Keyless uniquement après 429/403. Circuit breaker 60s + cache négatif.
/// Toutes les requêtes sont **sérialisées** (évite 3× 503 concurrents).
class GoogleBooksService {
  static String? get _apiKey => AppEnv.googleBooksApiKey;

  static bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  /// File d'attente globale : 1 HTTP Google Books à la fois.
  static Future<void> _gate = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() run) {
    late final Future<T> result;
    _gate = _gate.then((_) {
      result = run();
      return result.then<void>((_) {}, onError: (_) {});
    });
    return _gate.then((_) => result);
  }

  /// Uniquement après un vrai 429/403 avec clé — jamais après un 503.
  static bool _preferKeyless = false;

  /// Coupe-circuit : aucun HTTP tant que `now < lockedUntil`.
  static DateTime _googleBooksLockedUntil =
      DateTime.fromMillisecondsSinceEpoch(0);
  static const _lockDuration = Duration(seconds: 60);

  static bool get _isLocked =>
      DateTime.now().isBefore(_googleBooksLockedUntil);

  static void _tripBreaker([String reason = '']) {
    _googleBooksLockedUntil = DateTime.now().add(_lockDuration);
    if (kDebugMode) {
      debugPrint(
        'Google Books circuit OPEN 60s'
        '${reason.isEmpty ? '' : ' ($reason)'} — MangaDex/AniList only',
      );
    }
  }

  static bool _isServerError(int? code) =>
      code == 500 || code == 502 || code == 503 || code == 504;

  static bool _isQuotaError(int? code) => code == 429 || code == 403;

  static final Map<String, _CacheEntry> _memCache = {};
  static const _prefsPrefix = 'gb_cache_v1:';
  static const _ttl = Duration(hours: 24);
  static const _negativeTtl = Duration(minutes: 10);

  static Uri _volumesUri(Map<String, String> query, {required bool withKey}) {
    final params = Map<String, String>.from(query);
    // Jamais orderBy — Google trie déjà par pertinence ; orderBy→503.
    params.remove('orderBy');
    if (withKey) {
      final key = _apiKey;
      if (key != null && key.isNotEmpty) params['key'] = key;
    }
    return Uri.https('www.googleapis.com', '/books/v1/volumes', params);
  }

  static String _cacheKey(Map<String, String> params) {
    final clean = Map<String, String>.from(params)..remove('orderBy');
    final keys = clean.keys.toList()..sort();
    return keys.map((k) => '$k=${clean[k]}').join('&');
  }

  static Future<List<Map<String, String>>?> _readCache(String key) async {
    final mem = _memCache[key];
    if (mem != null && !mem.isExpired) return mem.hits;
    if (mem != null && mem.isExpired) _memCache.remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final ts = decoded['ts'] as int? ?? 0;
      final ttlMs = decoded['ttl_ms'] as int? ?? _ttl.inMilliseconds;
      if (DateTime.now().millisecondsSinceEpoch - ts > ttlMs) {
        await prefs.remove('$_prefsPrefix$key');
        return null;
      }
      final list = decoded['hits'] as List<dynamic>? ?? const [];
      final hits = list
          .map((e) => Map<String, String>.from(
                (e as Map).map((k, v) => MapEntry('$k', '$v')),
              ))
          .toList();
      _memCache[key] = _CacheEntry(
        hits,
        DateTime.fromMillisecondsSinceEpoch(ts),
        ttl: Duration(milliseconds: ttlMs),
      );
      return hits;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(
    String key,
    List<Map<String, String>> hits, {
    bool negative = false,
  }) async {
    final now = DateTime.now();
    final ttl = negative ? _negativeTtl : _ttl;
    _memCache[key] = _CacheEntry(hits, now, ttl: ttl);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefsPrefix$key',
        jsonEncode({
          'ts': now.millisecondsSinceEpoch,
          'ttl_ms': ttl.inMilliseconds,
          'hits': hits,
        }),
      );
    } catch (_) {}
  }

  static Future<http.Response?> _viaProxy(Map<String, String> p) async {
    try {
      // Proxy avec clé si dispo (évite 429 anonymes côté serveur).
      final withKey = hasApiKey && !_preferKeyless;
      final target = _volumesUri(p, withKey: withKey);
      final proxied = proxiedCatalogUri(target);
      final uri = kIsWeb
          ? proxied
          : Uri.parse(
              '${AppEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
              '/functions/v1/catalog-proxy'
              '?url=${Uri.encodeComponent(target.toString())}'
              '&apikey=${Uri.encodeComponent(AppEnv.supabaseAnonKey)}',
            );
      return await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'apikey': AppEnv.supabaseAnonKey,
              'Authorization': 'Bearer ${AppEnv.supabaseAnonKey}',
            },
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('Google Books proxy: $e');
      return null;
    }
  }

  /// GET volumes :
  /// - 503/5xx → retry **avec clé**, sans langRestrict, maxResults=20 → trip
  /// - 429/403 → seulement là keyless + proxy → trip
  static Future<http.Response?> _fetchVolumes(Map<String, String> params) async {
    if (_isLocked) return null;

    Future<http.Response> get(Uri uri) =>
        http.get(uri).timeout(const Duration(seconds: 6));

    final base = Map<String, String>.from(params)..remove('orderBy');

    // ——— Avec clé ———
    if (!_preferKeyless && hasApiKey) {
      try {
        final res = await get(_volumesUri(base, withKey: true));
        if (res.statusCode == 200) return res;

        // 503/5xx : retry AVEC clé, requête allégée (jamais keyless).
        if (_isServerError(res.statusCode)) {
          if (_isLocked) return null;
          final light = Map<String, String>.from(base)
            ..remove('langRestrict')
            ..['maxResults'] = '20';
          if (kDebugMode) {
            debugPrint(
              'Google Books ${res.statusCode} → retry keyed light (no langRestrict)',
            );
          }
          try {
            final retry = await get(_volumesUri(light, withKey: true));
            if (retry.statusCode == 200) return retry;
          } catch (_) {}
          _tripBreaker('server ${res.statusCode}');
          return null;
        }

        // 429/403 : autorise keyless pour la suite de la session.
        if (_isQuotaError(res.statusCode)) {
          _preferKeyless = true;
          if (kDebugMode) {
            debugPrint('Google Books ${res.statusCode} keyed → keyless OK');
          }
        } else {
          return res;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Google Books keyed: $e');
      }
    }

    if (_isLocked) return null;

    // ——— Keyless UNIQUEMENT après 429/403 ———
    if (_preferKeyless || !hasApiKey) {
      try {
        final res = await get(_volumesUri(base, withKey: false));
        if (res.statusCode == 200) return res;
        if (_isLocked) return null;
        if (_isQuotaError(res.statusCode) || _isServerError(res.statusCode)) {
          final proxyRes = await _viaProxy(base);
          if (proxyRes != null && proxyRes.statusCode == 200) return proxyRes;
          _tripBreaker(
            'keyless/proxy ${proxyRes?.statusCode ?? res.statusCode}',
          );
          return null;
        }
        return res;
      } catch (e) {
        if (kDebugMode) debugPrint('Google Books keyless: $e');
        if (!_isLocked) {
          final proxyRes = await _viaProxy(base);
          if (proxyRes != null && proxyRes.statusCode == 200) return proxyRes;
          _tripBreaker('keyless exception');
        }
        return null;
      }
    }

    return null;
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
        out.add(mapped);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, String>?> lookupByIsbn(String isbn) async {
    if (_isLocked) return null;
    for (final variant in OpenLibraryService.isbnLookupVariants(isbn)) {
      if (_isLocked) return null;
      try {
        final params = {'q': 'isbn:$variant', 'maxResults': '3'};
        final key = _cacheKey(params);
        final cached = await _readCache(key);
        if (cached != null) {
          return cached.isNotEmpty ? cached.first : null;
        }

        final response = await _fetchVolumes(params);
        if (response == null || response.statusCode != 200) {
          await _writeCache(key, const [], negative: true);
          continue;
        }
        final hits = _parseItems(response.body, isbnFallback: variant);
        await _writeCache(key, hits, negative: hits.isEmpty);
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
  }) {
    return _serialized(() => _searchImpl(
          query,
          maxResults: maxResults,
          startIndex: startIndex,
          langRestrict: langRestrict,
        ));
  }

  static Future<List<Map<String, String>>> _searchImpl(
    String query, {
    int maxResults = 20,
    int startIndex = 0,
    String? langRestrict = 'fr',
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];
    if (_isLocked) return [];

    try {
      // maxResults ≤ 25 : 40 + intitle: → 503 fréquents.
      final params = <String, String>{
        'q': q,
        'maxResults': '${maxResults.clamp(1, 25)}',
        'startIndex': '${startIndex.clamp(0, 200)}',
      };
      if (langRestrict != null && langRestrict.isNotEmpty) {
        params['langRestrict'] = langRestrict;
      }
      final key = _cacheKey(params);
      final cached = await _readCache(key);
      if (cached != null) return cached;

      final response = await _fetchVolumes(params);
      if (response == null || response.statusCode != 200) {
        await _writeCache(key, const [], negative: true);
        return [];
      }
      final hits = _parseItems(response.body);
      await _writeCache(key, hits, negative: hits.isEmpty);
      return hits;
    } catch (e) {
      if (kDebugMode) debugPrint('Google Books search: $e');
      return [];
    }
  }

  /// 1–3 pages **séquentielles**. Stop si la 1ʳᵉ requête renvoie déjà des tomes FR.
  /// Fallback souple `"$name" Tome` si `intitle:` → 0 / 503.
  static Future<List<Map<String, String>>> searchSeriesBatched(
    String seriesTitle, {
    String? author,
    int maxPages = 3,
    Duration pageDelay = const Duration(milliseconds: 400),
    String? langRestrict = 'fr',
    bool preferTomeQuery = true,
  }) async {
    final name = seriesTitle.trim();
    if (name.length < 2) return [];
    if (_isLocked) return [];
    final authorLast = author != null && author.trim().isNotEmpty
        ? author.trim().split(RegExp(r'\s+')).last
        : null;
    final queries = <String>[
      if (preferTomeQuery) 'intitle:"$name" Tome',
      if (authorLast != null && authorLast.length >= 2)
        'intitle:"$name" inauthor:"$authorLast"',
      // Fallback souple (évite totalItems:0 / 503 sur intitle: strict).
      if (preferTomeQuery) '"$name" Tome',
      if (authorLast != null && authorLast.length >= 2) '"$name" $authorLast',
      'intitle:"$name"',
      '"$name"',
    ];
    final out = <Map<String, String>>[];
    final seen = <String>{};
    final pages = maxPages.clamp(1, 3);
    for (final q in queries) {
      if (_isLocked) break;
      var gotBatch = false;
      for (var page = 0; page < pages; page++) {
        if (_isLocked) break;
        if (page > 0) await Future<void>.delayed(pageDelay);
        final batch = await search(
          q,
          maxResults: 25,
          startIndex: page * 25,
          langRestrict: langRestrict,
        );
        if (batch.isEmpty) break;
        gotBatch = true;
        for (final hit in batch) {
          final title = hit['title']?.trim().toLowerCase() ?? '';
          if (title.isEmpty || !seen.add(title)) continue;
          out.add(hit);
        }
        if (batch.length < 25) break;
      }
      // Assez de tomes FR numérotés → ne pas enchaîner les autres requêtes (anti-503).
      final frTomes = out.where((h) {
        final title = h['title'] ?? '';
        final lang = h['language'];
        if (!BookVfEdition.isFrenchLanguage(lang)) return false;
        return BookTitleParser.extractVolumeNumberStrict(title) != null;
      }).length;
      if (frTomes >= 3) break;
      if (gotBatch && out.length >= 15) break;
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
    if (BookVfEdition.isUsVolTitle(title)) return null;
    final subtitle = info['subtitle'] as String?;
    if (subtitle != null && BookVfEdition.isUsVolTitle(subtitle)) return null;
    if (BookVfEdition.isRejectedCatalogTitle(title, subtitle: subtitle)) {
      return null;
    }

    final langRaw = info['language'];
    final language = langRaw is List
        ? langRaw.map((e) => e.toString()).join(',')
        : langRaw?.toString();
    // FR + EN seulement — rejette it/es/sv/de/pt/nl/ru/da…
    if (!BookVfEdition.isFrOrEnLanguage(language)) return null;

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

    if (info['comicsContent'] == true) {
      result['comics_content'] = 'true';
    }
    final categories = info['categories'] as List<dynamic>?;
    if (categories != null && categories.isNotEmpty) {
      result['categories'] =
          categories.map((e) => e.toString()).join(', ');
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

    final apiVol = int.tryParse(result['series_volume'] ?? '');
    final parsed = BookTitleParser.parse(
      [title, ?subtitle].join(' : '),
      apiVolumeNumber: apiVol,
    );
    if (parsed.hasSeries) {
      result.putIfAbsent('series_title', () => parsed.seriesName!.trim());
    }
    if (parsed.hasVolume) {
      result['series_volume'] =
          parsed.volumeNumber!.round().toString();
    }

    return result;
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
  final Duration ttl;
  _CacheEntry(this.hits, this.at, {this.ttl = const Duration(hours: 24)});
  bool get isExpired => DateTime.now().difference(at) > ttl;
}
