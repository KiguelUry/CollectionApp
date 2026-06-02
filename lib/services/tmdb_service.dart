import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Films & séries — [TMDB](https://www.themoviedb.org/settings/api)
/// Clé : `TMDB_API_KEY` dans `.env`
class TmdbService {
  static String? get _apiKey {
    final k = dotenv.env['TMDB_API_KEY']?.trim();
    return k != null && k.isNotEmpty ? k : null;
  }

  static bool get isConfigured => _apiKey != null;

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    final key = _apiKey;
    if (key == null || q.length < 2) return [];

    try {
      final movieUri = Uri.https('api.themoviedb.org', '/3/search/movie', {
        'api_key': key,
        'query': q,
        'language': 'fr-FR',
        'page': '1',
      });
      final tvUri = Uri.https('api.themoviedb.org', '/3/search/tv', {
        'api_key': key,
        'query': q,
        'language': 'fr-FR',
        'page': '1',
      });

      final responses = await Future.wait([
        http.get(movieUri),
        http.get(tvUri),
      ]);

      final out = <Map<String, String>>[];

      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body) as Map<String, dynamic>;
        final list = data['results'] as List<dynamic>? ?? [];
        for (final raw in list.take(12)) {
          final m = _mapMovie(raw as Map<String, dynamic>);
          if (m != null) out.add(m);
        }
      }

      if (responses[1].statusCode == 200) {
        final data = jsonDecode(responses[1].body) as Map<String, dynamic>;
        final list = data['results'] as List<dynamic>? ?? [];
        for (final raw in list.take(8)) {
          final m = _mapTv(raw as Map<String, dynamic>);
          if (m != null) out.add(m);
        }
      }

      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB search: $e');
      return [];
    }
  }

  static Map<String, String>? _mapMovie(Map<String, dynamic> m) {
    final title = m['title']?.toString();
    if (title == null || title.isEmpty) return null;
    final year = (m['release_date'] as String?)?.substring(0, 4);
    final poster = m['poster_path']?.toString();
    return {
      'title': title,
      'image_url': poster != null ? 'https://image.tmdb.org/t/p/w342$poster' : '',
      'year': year ?? '',
      'media_kind': 'movie',
      'tmdb_id': m['id']?.toString() ?? '',
      'source': 'tmdb',
    };
  }

  static Map<String, String>? _mapTv(Map<String, dynamic> m) {
    final title = m['name']?.toString();
    if (title == null || title.isEmpty) return null;
    final year = (m['first_air_date'] as String?)?.substring(0, 4);
    final poster = m['poster_path']?.toString();
    return {
      'title': title,
      'image_url': poster != null ? 'https://image.tmdb.org/t/p/w342$poster' : '',
      'year': year ?? '',
      'media_kind': 'series',
      'tmdb_id': m['id']?.toString() ?? '',
      'source': 'tmdb',
    };
  }
}
