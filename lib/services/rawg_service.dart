import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../config/app_env.dart';
import '../config/supabase_public_config.dart';
import '../utils/catalog_http.dart';
import '../utils/search_relevance.dart';

class _CachedSearch {
  final List<Map<String, String>> games;
  final DateTime at;

  const _CachedSearch(this.games, this.at);
}

/// Jeux vidéo — recherche via proxy Supabase (web) ou RAWG direct (app).
class RawgService {
  static const _cacheTtl = Duration(minutes: 15);
  static const _cacheMax = 48;
  static final _cache = <String, _CachedSearch>{};

  static String? get _apiKey {
    final k = dotenv.env['RAWG_API_KEY']?.trim();
    return k != null && k.isNotEmpty ? k : null;
  }

  static bool get isConfigured => _apiKey != null;

  static bool get _proxyReady =>
      AppEnv.supabaseUrl.isNotEmpty && AppEnv.supabaseAnonKey.isNotEmpty;

  /// Web + app : proxy si Supabase configuré (CORS + cache serveur).
  static bool get useProxy => _proxyReady;

  static String? lastSearchError;

  static Uri _proxyUri(String query) {
    final base = SupabasePublicConfig.url.replaceAll(RegExp(r'/+$'), '');
    final anon = AppEnv.supabaseAnonKey;
    return Uri.parse('$base/functions/v1/rawg-api').replace(
      queryParameters: {
        'action': 'search',
        'query': query,
        'apikey': anon,
      },
    );
  }

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    lastSearchError = null;

    final cacheKey = q.toLowerCase();
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheTtl) {
      return cached.games.map((g) => Map<String, String>.from(g)).toList();
    }

    List<Map<String, String>> games;
    if (useProxy) {
      games = await _searchViaProxy(q);
    } else {
      games = await _searchDirect(q);
    }

    if (games.isNotEmpty) {
      _storeCache(cacheKey, games);
    }
    return games;
  }

  static void _storeCache(String key, List<Map<String, String>> games) {
    _cache[key] = _CachedSearch(
      games.map((g) => Map<String, String>.from(g)).toList(),
      DateTime.now(),
    );
    if (_cache.length <= _cacheMax) return;
    String? oldestKey;
    DateTime? oldestAt;
    for (final e in _cache.entries) {
      if (oldestAt == null || e.value.at.isBefore(oldestAt)) {
        oldestAt = e.value.at;
        oldestKey = e.key;
      }
    }
    if (oldestKey != null) _cache.remove(oldestKey);
  }

  static Future<List<Map<String, String>>> _searchViaProxy(String q) async {
    try {
      final anon = AppEnv.supabaseAnonKey;
      final response = await http
          .get(
            _proxyUri(q),
            headers: {
              'Accept': 'application/json',
              'apikey': anon,
              'Authorization': 'Bearer $anon',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200 || response.body.isEmpty) {
        lastSearchError = 'Recherche indisponible (${response.statusCode})';
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return [];
      final err = decoded['error'];
      if (err != null) {
        lastSearchError = err.toString();
        return [];
      }
      final raw = decoded['games'];
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((g) => g.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
          .where((g) => g['title']?.isNotEmpty == true)
          .toList();
    } catch (e) {
      lastSearchError = '$e';
      if (kDebugMode) debugPrint('RAWG proxy: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> _searchDirect(String q) async {
    final key = _apiKey;
    if (key == null) return [];

    try {
      final uri = Uri.https('api.rawg.io', '/api/games', {
        'key': key,
        'search': q,
        'page_size': '24',
      });
      final response = await http
          .get(uri, headers: catalogHttpHeaders)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['results'] as List<dynamic>? ?? [];
      final games = list
          .map((raw) => _mapGame(raw as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
      sortByScore(games, (g) => titleRelevanceScore(g['title']!, q));
      return games;
    } catch (e) {
      if (kDebugMode) debugPrint('RAWG direct: $e');
      return [];
    }
  }

  static Map<String, String>? _mapGame(Map<String, dynamic> g) {
    final name = g['name']?.toString();
    if (name == null || name.isEmpty) return null;

    final platforms = g['platforms'] as List<dynamic>?;
    final platformNames = platforms
            ?.map((p) => (p as Map)['platform']?['name']?.toString())
            .whereType<String>()
            .take(6)
            .join(', ') ??
        '';

    final released = g['released']?.toString();
    final year = released != null && released.length >= 4
        ? released.substring(0, 4)
        : '';

    final rating = g['rating'];
    final ratingStr =
        rating is num ? rating.toStringAsFixed(1) : rating?.toString() ?? '';

    return {
      'title': name,
      'image_url': g['background_image']?.toString() ?? '',
      'platform': platformNames,
      'year': year,
      'rawg_id': g['id']?.toString() ?? '',
      if (ratingStr.isNotEmpty) 'rawg_rating': ratingStr,
      'source': 'rawg',
    };
  }
}
