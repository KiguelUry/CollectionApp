import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../utils/catalog_http.dart';

/// Sets Lego — [Rebrickable](https://rebrickable.com/api/v3/docs/)
/// Clé : `REBRICKABLE_API_KEY` dans `.env`
class RebrickableService {
  static String? get _apiKey {
    final k = dotenv.env['REBRICKABLE_API_KEY']?.trim();
    return k != null && k.isNotEmpty ? k : null;
  }

  static bool get isConfigured => _apiKey != null;

  static Map<String, String> get _headers => {
        ...catalogHttpHeaders,
        if (_apiKey != null) 'Authorization': 'key $_apiKey',
      };

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (_apiKey == null || q.length < 2) return [];

    try {
      final uri = Uri.https('rebrickable.com', '/api/v3/lego/sets/', {
        'search': q,
        'page_size': '20',
      });
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('Rebrickable search ${response.statusCode}');
        }
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['results'] as List<dynamic>? ?? [];

      return list
          .map((raw) => _mapSet(raw as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Rebrickable search: $e');
      return [];
    }
  }

  static Future<Map<String, String>?> lookupSetNumber(String setNumber) async {
    final num = setNumber.trim();
    if (_apiKey == null || num.isEmpty) return null;

    try {
      final uri = Uri.https(
        'rebrickable.com',
        '/api/v3/lego/sets/$num/',
      );
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode != 200) return null;
      return _mapSet(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) debugPrint('Rebrickable set $num: $e');
      return null;
    }
  }

  static Map<String, String>? _mapSet(Map<String, dynamic> s) {
    final name = s['name']?.toString();
    if (name == null || name.isEmpty) return null;

    final setNum = s['set_num']?.toString() ?? '';
    final img = s['set_img_url']?.toString() ?? '';

    return {
      'title': name,
      'image_url': img,
      'set_number': setNum,
      'piece_count': s['num_parts']?.toString() ?? '',
      'year': s['year']?.toString() ?? '',
      'rebrickable_id': setNum,
      'source': 'rebrickable',
    };
  }
}
