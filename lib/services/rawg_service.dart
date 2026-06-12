import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../utils/catalog_http.dart';

/// Jeux vidéo — [RAWG](https://rawg.io/apidocs)
/// Clé : `RAWG_API_KEY` dans `.env`
class RawgService {
  static String? get _apiKey {
    final k = dotenv.env['RAWG_API_KEY']?.trim();
    return k != null && k.isNotEmpty ? k : null;
  }

  static bool get isConfigured => _apiKey != null;

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    final key = _apiKey;
    if (key == null || q.length < 2) return [];

    try {
      final uri = Uri.https('api.rawg.io', '/api/games', {
        'key': key,
        'search': q,
        'page_size': '20',
      });
      final response = await http.get(uri, headers: catalogHttpHeaders);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('RAWG ${response.statusCode}: ${response.body}');
        }
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['results'] as List<dynamic>? ?? [];

      return list
          .map((raw) => _mapGame(raw as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('RAWG search: $e');
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
            .take(3)
            .join(', ') ??
        '';

    final released = g['released']?.toString();
    final year = released != null && released.length >= 4
        ? released.substring(0, 4)
        : '';

    return {
      'title': name,
      'image_url': g['background_image']?.toString() ?? '',
      'platform': platformNames,
      'year': year,
      'rawg_id': g['id']?.toString() ?? '',
      'source': 'rawg',
    };
  }
}
