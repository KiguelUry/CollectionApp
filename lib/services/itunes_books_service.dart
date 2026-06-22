import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/catalog_http.dart';

/// Recherche livres / mangas / BD — API iTunes (gratuite, couvertures HD).
class ItunesBooksService {
  static Future<List<Map<String, String>>> search(
    String query, {
    int limit = 25,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    final ebook = await _searchEntity(q, entity: 'ebook', limit: limit);
    if (ebook.length >= 8) return ebook;

    final merged = <Map<String, String>>[];
    final seen = <String>{};
    for (final hit in [...ebook, ...await _searchEntity(q, entity: 'audiobook', limit: 12)]) {
      final key = (hit['title'] ?? '').toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      merged.add(hit);
    }
    return merged.take(limit).toList();
  }

  static Future<Map<String, String>?> lookupByIsbn(String isbn) async {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length < 10) return null;
    final hits = await search(cleaned, limit: 5);
    if (hits.isEmpty) return null;
    return hits.first;
  }

  static Future<List<Map<String, String>>> _searchEntity(
    String query, {
    required String entity,
    required int limit,
  }) async {
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'media': 'ebook',
        'entity': entity,
        'limit': '$limit',
        'country': 'FR',
        'lang': 'fr_fr',
      });
      final response = await http.get(uri, headers: catalogHttpHeaders);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('iTunes books ${response.statusCode}: ${response.body}');
        }
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['results'] as List<dynamic>? ?? [];

      return list
          .map((raw) => _mapBook(raw as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('iTunes books search: $e');
      return [];
    }
  }

  static Map<String, String>? _mapBook(Map<String, dynamic> m) {
    final title = m['trackName']?.toString() ??
        m['collectionName']?.toString();
    if (title == null || title.isEmpty) return null;

    final author = m['artistName']?.toString() ?? '';
    final series = m['collectionName']?.toString();
    final imageUrl = _hdArtwork(
      m['artworkUrl600']?.toString() ??
          m['artworkUrl100']?.toString() ??
          '',
    );

    final year = m['releaseDate']?.toString();
    final yearStr = year != null && year.length >= 4 ? year.substring(0, 4) : '';

    final result = <String, String>{
      'title': title,
      'author': author,
      'year': yearStr,
      'image_url': imageUrl,
      'itunes_id': m['trackId']?.toString() ?? '',
      'source': 'itunes',
    };

    if (series != null &&
        series.isNotEmpty &&
        series.toLowerCase() != title.toLowerCase()) {
      result['series_title'] = series;
    }

    final genres = m['genres'] as List<dynamic>?;
    if (genres != null && genres.isNotEmpty) {
      result['genre'] = genres.first.toString();
    }

    return result;
  }

  static String _hdArtwork(String url) {
    if (url.isEmpty) return '';
    return url
        .replaceFirst('100x100bb', '600x600bb')
        .replaceFirst('60x60bb', '600x600bb')
        .replaceFirst('http://', 'https://');
  }
}
