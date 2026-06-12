import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/catalog_http.dart';

/// Sets Lego — wiki Fandom (gratuit, sans clé). Secours si Rebrickable indisponible.
class LegoFandomService {
  static const _api = 'https://lego.fandom.com/api.php';

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final uri = Uri.parse(_api).replace(
        queryParameters: {
          'action': 'query',
          'format': 'json',
          'generator': 'search',
          'gsrsearch': q,
          'gsrlimit': '20',
          'prop': 'pageimages|pageterms',
          'piprop': 'thumbnail',
          'pithumbsize': '400',
        },
      );
      final response = await http.get(uri, headers: catalogHttpHeaders);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final pages = data['query']?['pages'] as Map<String, dynamic>?;
      if (pages == null) return [];

      final out = <Map<String, String>>[];
      for (final entry in pages.values) {
        final m = _mapPage(entry as Map<String, dynamic>);
        if (m != null) out.add(m);
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('Lego Fandom search: $e');
      return [];
    }
  }

  static Map<String, String>? _mapPage(Map<String, dynamic> p) {
    final title = p['title']?.toString();
    if (title == null || title.isEmpty) return null;
    if (title.startsWith('Category:') || title.startsWith('File:')) {
      return null;
    }

    final thumb = p['thumbnail'] as Map<String, dynamic>?;
    final img = thumb?['source']?.toString() ?? '';

    final setMatch = RegExp(r'\b(\d{4,5})\b').firstMatch(title);
    final setNum = setMatch?.group(1) ?? '';

    return {
      'title': title,
      'image_url': img,
      if (setNum.isNotEmpty) 'set_number': setNum,
      'source': 'lego_fandom',
      'lego_kind': 'lego',
    };
  }
}
