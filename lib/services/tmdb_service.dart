import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../utils/catalog_http.dart';

/// Films — [TMDB](https://www.themoviedb.org/settings/api)
/// Clé : `TMDB_API_KEY` dans `.env`
class TmdbService {
  static String? get _apiKey {
    final k = dotenv.env['TMDB_API_KEY']?.trim();
    return k != null && k.isNotEmpty ? k : null;
  }

  static bool get isConfigured => _apiKey != null;

  /// Films cinéma uniquement (pas les séries TV).
  static Future<List<Map<String, String>>> searchMovies(String query) async {
    final q = query.trim();
    final key = _apiKey;
    if (key == null || q.length < 2) return [];

    try {
      final uri = Uri.https('api.themoviedb.org', '/3/search/movie', {
        'api_key': key,
        'query': q,
        'language': 'fr-FR',
        'page': '1',
      });
      final response = await http.get(uri, headers: catalogHttpHeaders);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('TMDB movies ${response.statusCode}: ${response.body}');
        }
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['results'] as List<dynamic>? ?? [];

      return list
          .map((raw) => _mapMovie(raw as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('TMDB search: $e');
      return [];
    }
  }

  /// Compat — films seulement (les écrans utilisent [MovieCatalogService]).
  static Future<List<Map<String, String>>> search(String query) =>
      searchMovies(query);

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
      'physical_format': 'physical',
      'tmdb_id': m['id']?.toString() ?? '',
      'source': 'tmdb',
    };
  }
}
