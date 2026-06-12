import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/catalog_http.dart';

/// Recherche films — API iTunes (gratuite, sans clé). Blu-ray / DVD / VOD physique.
class ItunesMovieService {
  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': q,
        'media': 'movie',
        'entity': 'movie',
        'limit': '25',
        'country': 'FR',
        'lang': 'fr_fr',
      });
      final response = await http.get(uri, headers: catalogHttpHeaders);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('iTunes movies ${response.statusCode}: ${response.body}');
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
      if (kDebugMode) debugPrint('iTunes movie search: $e');
      return [];
    }
  }

  static Map<String, String>? _mapMovie(Map<String, dynamic> m) {
    final title = m['trackName']?.toString() ?? m['collectionName']?.toString();
    if (title == null || title.isEmpty) return null;

    var img = m['artworkUrl100']?.toString() ?? '';
    if (img.contains('100x100')) {
      img = img.replaceFirst('100x100bb', '600x600bb');
    }

    final year = m['releaseDate']?.toString();
    final yearStr = year != null && year.length >= 4 ? year.substring(0, 4) : '';

    return {
      'title': title,
      'image_url': img,
      'year': yearStr,
      'media_kind': 'movie',
      'physical_format': 'physical',
      'itunes_id': m['trackId']?.toString() ?? '',
      'source': 'itunes',
    };
  }
}
