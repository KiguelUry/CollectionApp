import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tcg_set_info.dart';
import '../utils/pokemon_series_labels_fr.dart';
import '../utils/pokemon_set_labels_fr.dart';
import '../utils/tcg_set_image_url.dart';
import '../utils/tcgdex_assets.dart';

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

      final blockFutures = seriesList.map((raw) async {
        final s = raw as Map<String, dynamic>;
        final serieId = s['id']?.toString() ?? '';
        if (serieId.isEmpty) return null;

        final setsRes = await http.get(_uri('/sets', {'serie.id': serieId}));
        if (setsRes.statusCode != 200) return null;

        final setsJson = jsonDecode(setsRes.body) as List<dynamic>;
        final serieName = s['name']?.toString() ?? serieId;
        final sets = setsJson
            .map((e) => _mapSetBrief(e as Map<String, dynamic>, serieName))
            .where((set) => set.id.isNotEmpty)
            .toList();
        if (sets.isEmpty) return null;

        sortSetsByReleaseNewest(sets);

        final blockLogo = normalizeTcgSetLogoUrl(
              tcgdexAssetUrl(s['logo'], kind: 'series', id: serieId),
            ) ??
            normalizeTcgSetLogoUrl(sets.firstOrNull?.imageUrl);

        return TcgSeriesBlock(
          id: serieId,
          name: serieName,
          nameFr: PokemonSeriesLabelsFr.label(serieName),
          imageUrl: blockLogo,
          sets: sets,
        );
      });

      final blocks = (await Future.wait(blockFutures))
          .whereType<TcgSeriesBlock>()
          .toList();

      sortBlocksByReleaseNewest(blocks);
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
      imageUrl: normalizeTcgSetLogoUrl(
        tcgdexAssetUrl(s['logo'], kind: 'set', id: id),
      ),
      symbolUrl: tcgdexAssetUrl(s['symbol'], kind: 'set', id: id),
      releaseDate: s['releaseDate']?.toString(),
      totalCards: cardCount?['official'] as int? ?? cardCount?['total'] as int?,
    );
  }

  /// TCGdex ne renvoie pas la rareté dans la liste — détail par carte.
  static const _detailBatchSize = 24;

  static Future<List<TcgCatalogCard>> fetchCardsInSet(String setId) async {
    if (setId.isEmpty) return [];
    try {
      final response = await http.get(
        _uri('/cards', {'set.id': setId}),
      );
      if (response.statusCode != 200) return [];

      final list = jsonDecode(response.body) as List<dynamic>;
      final ids = list
          .map((raw) => (raw as Map<String, dynamic>)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (ids.isEmpty) return [];

      final cards = <TcgCatalogCard>[];
      for (var i = 0; i < ids.length; i += _detailBatchSize) {
        final chunk = ids.skip(i).take(_detailBatchSize);
        final batch = await Future.wait(chunk.map(_fetchCardById));
        cards.addAll(batch.whereType<TcgCatalogCard>());
      }
      return cards;
    } catch (e) {
      if (kDebugMode) debugPrint('TCGdex cards in set $setId: $e');
      return [];
    }
  }

  static Future<TcgCatalogCard?> _fetchCardById(String id) async {
    try {
      final response = await http.get(_uri('/cards/$id'));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _mapCatalogFull(data);
    } catch (e) {
      if (kDebugMode) debugPrint('TCGdex card $id: $e');
      return null;
    }
  }

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final response = await http.get(_uri('/cards', {'name': q}));
      if (response.statusCode != 200) return [];

      final list = jsonDecode(response.body) as List<dynamic>;
      final ids = list
          .take(30)
          .map((raw) => (raw as Map<String, dynamic>)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final cards = await Future.wait(ids.map(_fetchCardById));
      return cards
          .whereType<TcgCatalogCard>()
          .map(
            (card) => {
              'title': card.name,
              'image_url': card.imageUrl ?? '',
              ...card.raw,
            },
          )
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

  static String? _imageUrl(dynamic image) {
    if (image is Map) {
      final high = image['high']?.toString();
      if (high != null && high.isNotEmpty) return high;
      final low = image['low']?.toString();
      if (low != null && low.isNotEmpty) return low;
    }
    final url = image?.toString();
    if (url == null || url.isEmpty) return null;
    if (url.contains('/high.') ||
        url.contains('/low.') ||
        url.endsWith('.webp') ||
        url.endsWith('.png') ||
        url.endsWith('.jpg')) {
      return url;
    }
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
      rarity: card['rarity']?.toString(),
      raw: _rawMeta(
        id,
        setId: setId,
        setName: '',
        number: card['localId']?.toString(),
        rarity: card['rarity']?.toString(),
        types: _typesList(card['types']),
      ),
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
        types: _typesList(card['types']),
      ),
    );
  }

  static List<String> _typesList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }

  static Map<String, String> _rawMeta(
    String id, {
    required String setId,
    String setName = '',
    String? setCode,
    String? number,
    String? rarity,
    List<String> types = const [],
  }) {
    return {
      'tcgdex_id': id,
      'pokemon_tcg_id': id,
      'set_id': setId,
      if (setCode != null && setCode.isNotEmpty) 'set_code': setCode,
      if (setName.isNotEmpty) 'set_name': setName,
      if (number != null && number.isNotEmpty) 'card_number': number,
      if (rarity != null && rarity.isNotEmpty) 'rarity': rarity,
      if (types.isNotEmpty) 'types': types.join(','),
      'source': 'tcgdex',
    };
  }
}
