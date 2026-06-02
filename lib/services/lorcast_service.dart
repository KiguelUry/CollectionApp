import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tcg_set_info.dart';
import '../utils/tcg_set_image_url.dart';

/// Lorcast — Disney Lorcana (gratuit, sans clé).
/// https://lorcast.com
class LorcastService {
  static Future<List<TcgSeriesBlock>> fetchBlocks() async {
    final sets = await _fetchAllSets();
    final main = <TcgSetInfo>[];
    final extra = <TcgSetInfo>[];

    for (final s in sets) {
      if (_isMainChapter(s.code)) {
        main.add(s);
      } else {
        extra.add(s);
      }
    }

    sortSetsByReleaseNewest(main);
    sortSetsByReleaseNewest(extra);

    return [
      TcgSeriesBlock(
        id: 'main',
        name: 'Chapitres',
        nameFr: 'Chapitres',
        sets: main,
      ),
      TcgSeriesBlock(
        id: 'promo',
        name: 'Promos & spéciaux',
        nameFr: 'Promos & spéciaux',
        sets: extra,
      ),
    ].where((b) => b.sets.isNotEmpty).toList();
  }

  static Future<List<TcgSetInfo>> _fetchAllSets() async {
    try {
      final url = Uri.https('api.lorcast.com', '/v0/sets');
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['results'] as List<dynamic>? ?? [];

      return list.map((raw) {
        final s = raw as Map<String, dynamic>;
        final code = s['code']?.toString() ?? '';
        return TcgSetInfo(
          id: s['id']?.toString() ?? code,
          name: s['name']?.toString() ?? code,
          code: code,
          seriesName: _isMainChapter(code) ? 'Chapitres' : 'Promos & spéciaux',
          imageUrl: code.isNotEmpty
              ? 'https://lorcast.com/images/sets/${code.toLowerCase()}.webp'
              : null,
          releaseDate: s['released_at']?.toString(),
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Lorcast sets: $e');
      return [];
    }
  }

  static Future<List<TcgCatalogCard>> fetchCardsInSet(String setIdOrCode) async {
    if (setIdOrCode.isEmpty) return [];
    try {
      final path = '/v0/sets/${Uri.encodeComponent(setIdOrCode)}/cards';
      final url = Uri.https('api.lorcast.com', path);
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body);
      final list = body is List
          ? body
          : (body as Map<String, dynamic>)['results'] as List<dynamic>? ??
              (body)['data'] as List<dynamic>? ??
              [];

      return list
          .map((c) => _mapCatalogCard(c as Map<String, dynamic>))
          .whereType<TcgCatalogCard>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Lorcast cards $setIdOrCode: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final url = Uri.https('api.lorcast.com', '/v0/cards/search', {
        'q': q,
      });
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cards = data['results'] as List<dynamic>? ??
          data['data'] as List<dynamic>? ??
          [];

      return cards
          .map((c) => _mapLegacy(c as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .take(24)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Lorcast search: $e');
      return [];
    }
  }

  static bool _isMainChapter(String? code) {
    final c = code?.trim() ?? '';
    if (c.isEmpty) return false;
    return int.tryParse(c) != null;
  }

  static TcgCatalogCard? _mapCatalogCard(Map<String, dynamic> card) {
    final baseName = card['name'] as String?;
    if (baseName == null || baseName.isEmpty) return null;

    final version = card['version'] as String?;
    final name = version != null && version.isNotEmpty
        ? '$baseName — $version'
        : baseName;

    final imageUris = card['image_uris'] as Map<String, dynamic>?;
    final digital = imageUris?['digital'] as Map<String, dynamic>?;
    final image = digital?['large']?.toString() ??
        digital?['normal']?.toString() ??
        card['image'] as String?;

    final set = card['set'] as Map<String, dynamic>?;
    final id = card['id']?.toString() ?? card['slug']?.toString() ?? '';

    return TcgCatalogCard(
      id: id,
      name: name,
      imageUrl: image,
      setName: set?['name']?.toString(),
      number: card['collector_number']?.toString(),
      rarity: card['rarity']?.toString(),
      raw: {
        'lorcast_id': id,
        'set_id': set?['id']?.toString() ?? '',
        'set_name': set?['name']?.toString() ?? '',
        'card_number': card['collector_number']?.toString() ?? '',
        'rarity': card['rarity']?.toString() ?? '',
        'source': 'lorcast',
      },
    );
  }

  static Map<String, String>? _mapLegacy(Map<String, dynamic> card) {
    final c = _mapCatalogCard(card);
    if (c == null) return null;
    return {
      'title': c.name,
      'image_url': c.imageUrl ?? '',
      ...c.raw,
    };
  }
}
