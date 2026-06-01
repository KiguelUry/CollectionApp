import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tcg_set_info.dart';
import '../utils/pokemon_series_labels_fr.dart';
import '../utils/pokemon_set_labels_fr.dart';

/// Pokémon — [TCGdex](https://tcgdex.dev) (gratuit, multilingue FR, sans clé).
/// Remplace pokemontcg.io / Scrydex.
class PokemonTcgService {
  static const _base = 'https://api.tcgdex.net/v2/fr';

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$_base$path').replace(queryParameters: query);
  }

  static Future<List<TcgSeriesBlock>> fetchBlocks() async {
    try {
      final seriesRes = await http.get(_uri('/series'));
      if (seriesRes.statusCode != 200) return [];

      final seriesList = jsonDecode(seriesRes.body) as List<dynamic>;
      final blocks = <TcgSeriesBlock>[];

      for (final raw in seriesList) {
        final s = raw as Map<String, dynamic>;
        final serieId = s['id']?.toString() ?? '';
        if (serieId.isEmpty) continue;

        final setsRes = await http.get(
          _uri('/sets', {'serie.id': serieId}),
        );
        if (setsRes.statusCode != 200) continue;

        final setsJson = jsonDecode(setsRes.body) as List<dynamic>;
        final sets = setsJson
            .map((e) => _mapSetBrief(e as Map<String, dynamic>, serieId))
            .where((set) => set.id.isNotEmpty)
            .toList();
        if (sets.isEmpty) continue;

        sets.sort((a, b) => b.id.compareTo(a.id));

        final serieName = s['name']?.toString() ?? serieId;
        blocks.add(
          TcgSeriesBlock(
            id: serieId,
            name: serieName,
            nameFr: PokemonSeriesLabelsFr.label(serieName),
            sets: sets,
          ),
        );
      }

      blocks.sort(
        (a, b) => PokemonSeriesLabelsFr.sortIndex(a.name)
            .compareTo(PokemonSeriesLabelsFr.sortIndex(b.name)),
      );
      return blocks;
    } catch (e) {
      if (kDebugMode) debugPrint('TCGdex blocks: $e');
      return [];
    }
  }

  static TcgSetInfo _mapSetBrief(Map<String, dynamic> s, String serieName) {
    final id = s['id']?.toString() ?? '';
    final name = s['name']?.toString() ?? id;
    final abbr = s['abbreviation'] as Map<String, dynamic>?;
    final code = abbr?['official']?.toString() ?? id;
    final cardCount = s['cardCount'] as Map<String, dynamic>?;

    return TcgSetInfo(
      id: id,
      name: name,
      nameFr: PokemonSetLabelsFr.setLabel(code, name),
      code: code,
      seriesName: serieName,
      imageUrl: s['logo']?.toString(),
      symbolUrl: s['symbol']?.toString(),
      releaseDate: s['releaseDate']?.toString(),
      totalCards: cardCount?['official'] as int? ?? cardCount?['total'] as int?,
    );
  }

  static Future<List<TcgCatalogCard>> fetchCardsInSet(String setId) async {
    if (setId.isEmpty) return [];
    try {
      final response = await http.get(
        _uri('/cards', {'set.id': setId}),
      );
      if (response.statusCode != 200) return [];

      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((raw) => _mapCatalogBrief(raw as Map<String, dynamic>, setId))
          .whereType<TcgCatalogCard>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('TCGdex cards in set $setId: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final response = await http.get(_uri('/cards', {'name': q}));
      if (response.statusCode != 200) return [];

      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .take(30)
          .map((raw) {
            final brief = raw as Map<String, dynamic>;
            final id = brief['id']?.toString() ?? '';
            final card = _mapCatalogBrief(brief, _setIdFromCardId(id));
            if (card == null) return null;
            return {
              'title': card.name,
              'image_url': card.imageUrl ?? '',
              ...card.raw,
            };
          })
          .whereType<Map<String, String>>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('TCGdex search: $e');
      return [];
    }
  }

  static String _setIdFromCardId(String cardId) {
    final dash = cardId.lastIndexOf('-');
    if (dash <= 0) return '';
    return cardId.substring(0, dash);
  }

  static String? _imageUrl(dynamic base) {
    final url = base?.toString();
    if (url == null || url.isEmpty) return null;
    if (url.contains('/high.') || url.contains('/low.')) return url;
    return '$url/high.webp';
  }

  static TcgCatalogCard? _mapCatalogBrief(
    Map<String, dynamic> card,
    String setId,
  ) {
    final name = card['name'] as String?;
    if (name == null || name.isEmpty) return null;

    final id = card['id']?.toString() ?? '';
    return TcgCatalogCard(
      id: id,
      name: name,
      imageUrl: _imageUrl(card['image']),
      number: card['localId']?.toString(),
      raw: _rawMeta(id, setId: setId, setName: '', number: card['localId']?.toString()),
    );
  }

  static TcgCatalogCard? _mapCatalogFull(Map<String, dynamic> card) {
    final name = card['name'] as String?;
    if (name == null || name.isEmpty) return null;

    final id = card['id']?.toString() ?? '';
    final set = card['set'] as Map<String, dynamic>?;
    final setId = set?['id']?.toString() ?? _setIdFromCardId(id);
    final abbr = set?['abbreviation'] as Map<String, dynamic>?;

    return TcgCatalogCard(
      id: id,
      name: name,
      imageUrl: _imageUrl(card['image']),
      setName: set?['name']?.toString(),
      number: card['localId']?.toString(),
      rarity: card['rarity']?.toString(),
      raw: _rawMeta(
        id,
        setId: setId,
        setName: set?['name']?.toString() ?? '',
        setCode: abbr?['official']?.toString(),
        number: card['localId']?.toString(),
        rarity: card['rarity']?.toString(),
      ),
    );
  }

  static Map<String, String> _rawMeta(
    String id, {
    required String setId,
    String setName = '',
    String? setCode,
    String? number,
    String? rarity,
  }) {
    return {
      'tcgdex_id': id,
      'pokemon_tcg_id': id,
      'set_id': setId,
      if (setCode != null && setCode.isNotEmpty) 'set_code': setCode,
      if (setName.isNotEmpty) 'set_name': setName,
      if (number != null && number.isNotEmpty) 'card_number': number,
      if (rarity != null && rarity.isNotEmpty) 'rarity': rarity,
      'source': 'tcgdex',
    };
  }
}
