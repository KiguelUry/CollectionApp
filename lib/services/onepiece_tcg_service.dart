import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tcg_set_info.dart';
import '../utils/tcg_set_image_url.dart';

/// API communautaire One Piece TCG (gratuit).
/// https://www.optcgapi.com
class OnepieceTcgService {
  static Future<List<TcgSeriesBlock>> fetchBlocks() async {
    final sets = await _fetchAllSets();
    final byBlock = <String, List<TcgSetInfo>>{};

    for (final s in sets) {
      byBlock.putIfAbsent(_blockForSetId(s.code ?? s.id), () => []).add(s);
    }

    final blocks = byBlock.entries.map((e) {
      final sorted = List<TcgSetInfo>.from(e.value)
        ..sort((a, b) => compareOnepieceSetId(a.id, b.id));
      return TcgSeriesBlock(
        id: e.key,
        name: e.key,
        imageUrl: sorted.firstOrNull?.imageUrl,
        sets: sorted,
      );
    }).toList();

    blocks.sort((a, b) {
      final latestA = a.sets.isNotEmpty ? a.sets.first.id : '';
      final latestB = b.sets.isNotEmpty ? b.sets.first.id : '';
      return compareOnepieceSetId(latestB, latestA);
    });

    await _enrichBlockLogos(blocks);
    return blocks;
  }

  static Future<List<TcgSetInfo>> _fetchAllSets() async {
    try {
      final url = Uri.https('www.optcgapi.com', '/api/allSets/');
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body);
      final list = body is List ? body : <dynamic>[];

      return list.map((raw) {
        final s = raw as Map<String, dynamic>;
        final setId = s['set_id']?.toString() ?? '';
        final name = s['set_name']?.toString() ?? setId;
        return TcgSetInfo(
          id: setId,
          name: name,
          code: setId,
          seriesName: _blockForSetId(setId),
          imageUrl: onepieceSetLogoUrl(setId),
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('One Piece sets: $e');
      return [];
    }
  }

  static Future<List<TcgCatalogCard>> fetchCardsInSet(String setId) async {
    if (setId.isEmpty) return [];
    try {
      final path = '/api/sets/${Uri.encodeComponent(setId)}/';
      final url = Uri.https('www.optcgapi.com', path);
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body);
      final list = body is List
          ? body
          : (body as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];

      return list
          .map((c) => _mapCatalogCard(c as Map<String, dynamic>))
          .whereType<TcgCatalogCard>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('One Piece cards $setId: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final url = Uri.https('www.optcgapi.com', '/api/cards/search', {
        'name': q,
      });
      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body);
      final list = body is List
          ? body
          : (body as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];

      return list
          .map((c) => _mapLegacy(c as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .take(24)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('One Piece TCG search: $e');
      return [];
    }
  }

  /// Vignette bloc : première carte du set le plus récent (pas de logo officiel fiable).
  static Future<void> _enrichBlockLogos(List<TcgSeriesBlock> blocks) async {
    const batchSize = 4;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.imageUrl != null && block.imageUrl!.isNotEmpty) continue;
      final set = block.sets.isNotEmpty ? block.sets.first : null;
      if (set == null) continue;

      final cards = await fetchCardsInSet(set.id);
      final thumb = cards.isNotEmpty ? cards.first.imageUrl : null;
      if (thumb == null || thumb.isEmpty) continue;

      blocks[i] = TcgSeriesBlock(
        id: block.id,
        name: block.name,
        nameFr: block.nameFr,
        imageUrl: thumb,
        sets: block.sets,
      );

      if (i > 0 && i % batchSize == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  static String _blockForSetId(String setId) {
    final id = setId.toUpperCase();
    if (id.startsWith('OP')) return 'Boosters (OP)';
    if (id.startsWith('EB')) return 'Extra Boosters';
    if (id.startsWith('PRB')) return 'Premium Boosters';
    if (id.startsWith('ST')) return 'Starter Decks';
    return 'Autres';
  }

  static TcgCatalogCard? _mapCatalogCard(Map<String, dynamic> card) {
    final name = card['card_name'] as String? ??
        card['name'] as String? ??
        card['cardName'] as String?;
    if (name == null || name.isEmpty) return null;

    final cardSetId = card['card_set_id']?.toString() ?? '';
    final setId = card['set_id']?.toString() ?? '';

    return TcgCatalogCard(
      id: cardSetId.isNotEmpty ? cardSetId : (card['id']?.toString() ?? name),
      name: name,
      imageUrl: card['card_image']?.toString() ?? card['image']?.toString(),
      setName: card['set_name']?.toString(),
      number: cardSetId,
      rarity: card['rarity']?.toString(),
      raw: {
        'onepiece_card_id': cardSetId.isNotEmpty
            ? cardSetId
            : (card['card_id']?.toString() ?? card['id']?.toString() ?? ''),
        'set_id': setId,
        'set_name': card['set_name']?.toString() ?? '',
        'card_number': cardSetId,
        'rarity': card['rarity']?.toString() ?? '',
        'source': 'optcg',
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
