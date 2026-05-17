import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/search_relevance.dart';

/// API gratuite Open Library — équivalent « catalogue » pour les livres.
/// https://openlibrary.org/developers/api
class OpenLibraryService {
  static Future<List<Map<String, String>>> searchBooks(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];

    try {
      final url = Uri.https('openlibrary.org', '/search.json', {
        'q': trimmed,
        'limit': '30',
        'fields': 'key,title,author_name,first_publish_year,cover_i,ratings_average,ratings_count',
        'sort': 'rating',
      });
      final response = await http.get(url);

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['docs'] as List<dynamic>? ?? [];

      final results = <Map<String, String>>[];
      for (final raw in docs) {
        final doc = raw as Map<String, dynamic>;
        final title = doc['title'] as String? ?? 'Sans titre';
        final authors = doc['author_name'] as List<dynamic>?;
        final author = authors?.isNotEmpty == true
            ? authors!.first.toString()
            : 'Auteur inconnu';
        final year = doc['first_publish_year']?.toString() ?? '';
        final coverId = doc['cover_i']?.toString();
        final imageUrl = coverId != null
            ? 'https://covers.openlibrary.org/b/id/$coverId-M.jpg'
            : '';
        final ratingAvg = (doc['ratings_average'] as num?)?.toDouble();
        final ratingCount = (doc['ratings_count'] as int?) ?? 0;

        results.add({
          'key': doc['key']?.toString() ?? '',
          'title': title,
          'author': author,
          'year': year,
          'image_url': imageUrl,
          if (ratingAvg != null) 'rating_avg': ratingAvg.toStringAsFixed(1),
          'rating_count': ratingCount.toString(),
        });
      }

      sortByScore(
        results,
        (b) {
          final rel = titleRelevanceScore(b['title']!, trimmed);
          final authorRel = titleRelevanceScore(b['author'] ?? '', trimmed);
          final count = int.tryParse(b['rating_count'] ?? '0') ?? 0;
          final avg =
              double.tryParse(b['rating_avg'] ?? '') ?? 0;
          final popularity = (count * avg * 10).round();
          return rel * 10 + authorRel * 5 + popularity;
        },
      );

      return results.take(20).toList();
    } catch (e) {
      debugPrint('Erreur recherche Open Library: $e');
      return [];
    }
  }
}
