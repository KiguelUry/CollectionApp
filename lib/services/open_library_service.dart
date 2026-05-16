import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// API gratuite Open Library — équivalent « catalogue » pour les livres.
/// https://openlibrary.org/developers/api
class OpenLibraryService {
  static Future<List<Map<String, String>>> searchBooks(String query) async {
    if (query.trim().length < 2) return [];

    try {
      final url = Uri.https('openlibrary.org', '/search.json', {
        'q': query.trim(),
        'limit': '25',
        'fields': 'key,title,author_name,first_publish_year,cover_i',
      });
      final response = await http.get(url);

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['docs'] as List<dynamic>? ?? [];

      return docs.map((raw) {
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

        return {
          'key': doc['key']?.toString() ?? '',
          'title': title,
          'author': author,
          'year': year,
          'image_url': imageUrl,
        };
      }).toList();
    } catch (e) {
      debugPrint('Erreur recherche Open Library: $e');
      return [];
    }
  }
}
