import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/catalog_http.dart';

/// Recherche jeux — API publique du store Steam (gratuite, sans clé).
class SteamStoreService {
  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final uri = Uri.https('store.steampowered.com', '/api/storesearch/', {
        'term': q,
        'l': 'french',
        'cc': 'FR',
      });
      final response = await http.get(uri, headers: catalogHttpHeaders);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('Steam search ${response.statusCode}');
        }
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['items'] as List<dynamic>? ?? [];

      return list
          .map((raw) => _mapGame(raw as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Steam search: $e');
      return [];
    }
  }

  static Map<String, String>? _mapGame(Map<String, dynamic> g) {
    final name = g['name']?.toString();
    if (name == null || name.isEmpty) return null;

    return {
      'title': name,
      'image_url': g['tiny_image']?.toString() ?? '',
      'platform': 'PC (Steam)',
      'steam_appid': g['id']?.toString() ?? '',
      'source': 'steam',
    };
  }
}
