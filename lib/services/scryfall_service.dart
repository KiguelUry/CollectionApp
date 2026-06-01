import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tcg_set_info.dart';

/// Scryfall — Magic: The Gathering (gratuit, sans clé).
class ScryfallService {
  static Future<List<TcgSeriesBlock>> fetchBlocks() async {
    try {
      final url = Uri.https('api.scryfall.com', '/sets');
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];
      final sets = <TcgSetInfo>[];

      for (final raw in list) {
        final s = raw as Map<String, dynamic>;
        final setType = s['set_type'] as String? ?? '';
        if (setType == 'memorabilia' || setType == 'funny') continue;

        sets.add(
          TcgSetInfo(
            id: s['id']?.toString() ?? '',
            name: s['name']?.toString() ?? '',
            code: s['code']?.toString(),
            seriesName: s['block']?.toString() ?? s['block_code']?.toString() ?? 'Autre',
            imageUrl: s['icon_svg_uri']?.toString(),
            releaseDate: s['released_at']?.toString(),
            totalCards: s['card_count'] as int?,
          ),
        );
      }

      final byBlock = <String, List<TcgSetInfo>>{};
      for (final s in sets) {
        byBlock.putIfAbsent(s.seriesName, () => []).add(s);
      }

      return byBlock.entries.map((e) {
        final sorted = List<TcgSetInfo>.from(e.value)
          ..sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
        return TcgSeriesBlock(
          id: e.key,
          name: e.key,
          sets: sorted,
        );
      }).toList()
        ..sort((a, b) => (b.sets.firstOrNull?.releaseDate ?? '')
            .compareTo(a.sets.firstOrNull?.releaseDate ?? ''));
    } catch (e) {
      if (kDebugMode) debugPrint('Scryfall sets: $e');
      return [];
    }
  }

  static Future<List<TcgCatalogCard>> fetchCardsInSet(String setCode) async {
    if (setCode.isEmpty) return [];
    try {
      final url = Uri.https('api.scryfall.com', '/cards/search', {
        'q': 'set:$setCode',
        'unique': 'cards',
        'order': 'set',
      });
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cards = data['data'] as List<dynamic>? ?? [];
      return cards
          .map((c) {
            final m = _mapCard(c as Map<String, dynamic>);
            if (m == null) return null;
            return TcgCatalogCard(
              id: m['scryfall_id'] ?? '',
              name: m['title'] ?? '',
              imageUrl: m['image_url'],
              setName: m['set_name'],
              number: m['card_number'],
              rarity: m['rarity'],
              raw: m,
            );
          })
          .whereType<TcgCatalogCard>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Scryfall set cards: $e');
      return [];
    }
  }  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final url = Uri.https('api.scryfall.com', '/cards/search', {
        'q': q,
        'unique': 'cards',
        'order': 'released',
      });
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cards = data['data'] as List<dynamic>? ?? [];
      return cards
          .map((c) => _mapCard(c as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .take(24)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Scryfall: $e');
      return [];
    }
  }

  static Map<String, String>? _mapCard(Map<String, dynamic> card) {
    final name = card['name'] as String?;
    if (name == null || name.isEmpty) return null;

    final setName = card['set_name'] as String? ?? '';
    final collector = card['collector_number'] as String? ?? '';
    final rarity = card['rarity'] as String? ?? '';
    String? image =
        (card['image_uris'] as Map<String, dynamic>?)?['normal'] as String?;
    if (image == null) {
      final faces = card['card_faces'] as List<dynamic>?;
      if (faces != null && faces.isNotEmpty) {
        final face = faces.first as Map<String, dynamic>;
        image = (face['image_uris'] as Map<String, dynamic>?)?['normal']
            as String?;
      }
    }

    return {
      'title': name,
      'image_url': image ?? '',
      'set_name': setName,
      'card_number': collector,
      'rarity': rarity,
      'scryfall_id': card['id']?.toString() ?? '',
      'source': 'scryfall',
    };
  }
}
