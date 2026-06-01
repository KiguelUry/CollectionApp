import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tcg_set_info.dart';

/// YGOProDeck — Yu-Gi-Oh! (gratuit).
class YgoprodeckService {
  static Future<List<TcgSeriesBlock>> fetchBlocks() async {
    final sets = await _fetchAllSets();
    final byEra = <String, List<TcgSetInfo>>{};

    for (final s in sets) {
      final era = _eraLabel(s.releaseDate);
      byEra.putIfAbsent(era, () => []).add(s);
    }

    final blocks = byEra.entries
        .map(
          (e) => TcgSeriesBlock(
            id: e.key,
            name: e.key,
            sets: e.value
              ..sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? '')),
          ),
        )
        .toList();

    blocks.sort((a, b) => _eraSortIndex(a.name).compareTo(_eraSortIndex(b.name)));
    return blocks;
  }

  static Future<List<TcgSetInfo>> _fetchAllSets() async {
    try {
      final url = Uri.https('db.ygoprodeck.com', '/api/v7/cardsets.php');
      final response = await http.get(url);
      if (response.statusCode != 200) return [];

      final list = jsonDecode(response.body) as List<dynamic>;
      return list.map((raw) {
        final s = raw as Map<String, dynamic>;
        final name = s['set_name']?.toString() ?? '';
        final code = s['set_code']?.toString();
        return TcgSetInfo(
          id: name,
          name: name,
          code: code,
          seriesName: _eraLabel(s['tcg_date']?.toString()),
          imageUrl: s['set_image']?.toString(),
          releaseDate: s['tcg_date']?.toString(),
          totalCards: s['num_of_cards'] as int?,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('YGOProDeck sets: $e');
      return [];
    }
  }

  static Future<List<TcgCatalogCard>> fetchCardsInSet(String setName) async {
    if (setName.isEmpty) return [];
    final out = <TcgCatalogCard>[];
    var offset = 0;
    const pageSize = 100;

    while (offset < 5000) {
      try {
        final url = Uri.https('db.ygoprodeck.com', '/api/v7/cardinfo.php', {
          'cardset': setName,
          'num': '$pageSize',
          'offset': '$offset',
        });
        final response = await http.get(url);
        if (response.statusCode != 200) break;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final cards = data['data'] as List<dynamic>? ?? [];
        if (cards.isEmpty) break;

        for (final raw in cards) {
          final c = _mapCatalogCard(raw as Map<String, dynamic>, setName);
          if (c != null) out.add(c);
        }

        if (cards.length < pageSize) break;
        offset += pageSize;
      } catch (e) {
        if (kDebugMode) debugPrint('YGOProDeck cards $setName: $e');
        break;
      }
    }
    return out;
  }

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final url = Uri.https('db.ygoprodeck.com', '/api/v7/cardinfo.php', {
        'fname': q,
        'num': '25',
      });
      final response = await http.get(url);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cards = data['data'] as List<dynamic>? ?? [];
      return cards
          .map((c) => _mapLegacy(c as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('YGOProDeck search: $e');
      return [];
    }
  }

  static String _eraLabel(String? tcgDate) {
    if (tcgDate == null || tcgDate.length < 4) return 'Date inconnue';
    final year = int.tryParse(tcgDate.substring(0, 4)) ?? 0;
    if (year >= 2024) return '2024 et après';
    if (year >= 2020) return '2020 – 2023';
    if (year >= 2015) return '2015 – 2019';
    if (year >= 2010) return '2010 – 2014';
    if (year >= 2005) return '2005 – 2009';
    if (year >= 2000) return '2000 – 2004';
    return 'Classique';
  }

  static int _eraSortIndex(String era) {
    const order = [
      '2024 et après',
      '2020 – 2023',
      '2015 – 2019',
      '2010 – 2014',
      '2005 – 2009',
      '2000 – 2004',
      'Classique',
      'Date inconnue',
    ];
    final i = order.indexOf(era);
    return i >= 0 ? i : order.length;
  }

  static TcgCatalogCard? _mapCatalogCard(
    Map<String, dynamic> card,
    String setName,
  ) {
    final name = card['name'] as String?;
    if (name == null || name.isEmpty) return null;

    final images = card['card_images'] as List<dynamic>?;
    final imageUrl = images?.isNotEmpty == true
        ? (images!.first as Map)['image_url']?.toString() ?? ''
        : '';

    final sets = card['card_sets'] as List<dynamic>?;
    String setCode = '';
    if (sets != null) {
      for (final raw in sets) {
        final s = raw as Map<String, dynamic>;
        if (s['set_name']?.toString() == setName) {
          setCode = s['set_code']?.toString() ?? '';
          break;
        }
      }
      if (setCode.isEmpty && sets.isNotEmpty) {
        setCode = (sets.first as Map)['set_code']?.toString() ?? '';
      }
    }

    final id = card['id']?.toString() ?? '';
    return TcgCatalogCard(
      id: id,
      name: name,
      imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
      setName: setName,
      rarity: card['type']?.toString(),
      raw: {
        'ygoprodeck_id': id,
        'set_name': setName,
        'set_code': setCode,
        'source': 'ygoprodeck',
      },
    );
  }

  static Map<String, String>? _mapLegacy(Map<String, dynamic> card) {
    final sets = card['card_sets'] as List<dynamic>?;
    final setName = sets?.isNotEmpty == true
        ? (sets!.first as Map)['set_name']?.toString() ?? ''
        : '';
    final c = _mapCatalogCard(card, setName);
    if (c == null) return null;
    return {
      'title': c.name,
      'image_url': c.imageUrl ?? '',
      ...c.raw,
    };
  }
}
