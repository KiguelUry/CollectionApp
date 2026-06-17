import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/pokemon_card_lang.dart';
import '../models/tcg_set_info.dart';
import '../utils/pokemon_series_labels_fr.dart';
import '../utils/pokemon_set_labels_fr.dart';
import '../utils/tcg_set_image_url.dart';
import '../utils/tcgdex_assets.dart';

/// Pokémon — [TCGdex](https://tcgdex.dev) (gratuit, multilingue, sans clé).
class PokemonTcgService {
  static String catalogKey(String tcgdexId, {String lang = PokemonCardLang.fr}) =>
      PokemonCardLang.catalogKey(tcgdexId, lang: lang);

  static Uri _uri(String lang, String path, [Map<String, String>? query]) {
    return Uri.parse('https://api.tcgdex.net/v2/$lang$path')
        .replace(queryParameters: query);
  }

  static Future<List<TcgSeriesBlock>> fetchBlocks({
    String lang = PokemonCardLang.fr,
  }) async {
    try {
      final seriesRes = await http.get(_uri(lang, '/series'));
      if (seriesRes.statusCode != 200) return [];

      final seriesList = jsonDecode(seriesRes.body) as List<dynamic>;

      final blockFutures = seriesList.map((raw) async {
        final s = raw as Map<String, dynamic>;
        final serieId = s['id']?.toString() ?? '';
        if (serieId.isEmpty) return null;

        final setsRes = await http.get(_uri(lang, '/sets', {'serie.id': serieId}));
        if (setsRes.statusCode != 200) return null;

        final setsJson = jsonDecode(setsRes.body) as List<dynamic>;
        final serieName = s['name']?.toString() ?? serieId;
        final sets = setsJson
            .map((e) => _mapSetBrief(e as Map<String, dynamic>, serieName, lang))
            .where((set) => set.id.isNotEmpty)
            .toList();
        if (sets.isEmpty) return null;

        sortSetsByReleaseNewest(sets);

        final blockLogo = normalizeTcgSetLogoUrl(
              tcgdexAssetUrl(
                s['logo'],
                kind: 'series',
                id: serieId,
                lang: lang,
              ),
            ) ??
            normalizeTcgSetLogoUrl(sets.firstOrNull?.imageUrl);

        return TcgSeriesBlock(
          id: serieId,
          name: serieName,
          nameFr: lang == PokemonCardLang.fr
              ? PokemonSeriesLabelsFr.label(serieName)
              : null,
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
      if (kDebugMode) debugPrint('TCGdex blocks ($lang): $e');
      return [];
    }
  }

  static TcgSetInfo _mapSetBrief(
    Map<String, dynamic> s,
    String serieName,
    String lang,
  ) {
    final id = s['id']?.toString() ?? '';
    final name = s['name']?.toString() ?? id;
    final abbr = s['abbreviation'] as Map<String, dynamic>?;
    final code = abbr?['official']?.toString() ?? id;
    final cardCount = s['cardCount'] as Map<String, dynamic>?;

    return TcgSetInfo(
      id: id,
      name: name,
      nameFr: lang == PokemonCardLang.fr
          ? PokemonSetLabelsFr.setLabel(code, name)
          : null,
      code: code,
      seriesName: serieName,
      imageUrl: normalizeTcgSetLogoUrl(
        tcgdexAssetUrl(s['logo'], kind: 'set', id: id, lang: lang),
      ),
      symbolUrl: tcgdexAssetUrl(s['symbol'], kind: 'set', id: id, lang: lang),
      releaseDate: s['releaseDate']?.toString(),
      totalCards: cardCount?['official'] as int? ?? cardCount?['total'] as int?,
    );
  }

  static Future<List<TcgCatalogCard>> fetchCardsInSet(
    String setId, {
    String lang = PokemonCardLang.fr,
    TcgSetInfo? setInfo,
  }) async {
    if (setId.isEmpty) return [];
    try {
      final response = await http.get(
        _uri(lang, '/cards', {'set.id': setId}),
      );
      if (response.statusCode != 200) return [];

      final list = jsonDecode(response.body) as List<dynamic>;
      final cards = list
          .map(
            (raw) => _mapCatalogBrief(
              raw as Map<String, dynamic>,
              setId,
              lang: lang,
              setInfo: setInfo,
            ),
          )
          .whereType<TcgCatalogCard>()
          .toList();

      fillMissingCardImages(cards);
      return cards;
    } catch (e) {
      if (kDebugMode) debugPrint('TCGdex cards in set $setId ($lang): $e');
      return [];
    }
  }

  static const _rarityBatch = 30;
  static const _searchPageSize = 100;
  static const _searchMaxPages = 5;

  static String? tcgdexCardImageUrl(
    String cardId, {
    String? localId,
    String lang = PokemonCardLang.fr,
  }) {
    final dash = cardId.lastIndexOf('-');
    if (dash <= 0) return null;
    final setId = cardId.substring(0, dash);
    final num = localId ?? cardId.substring(dash + 1);
    final seriesMatch = RegExp(r'^[a-zA-Z]+').firstMatch(setId);
    final series = seriesMatch?.group(0);
    if (series == null || series.isEmpty || num.isEmpty) return null;
    return 'https://assets.tcgdex.net/$lang/$series/$setId/$num/high.webp';
  }

  static void fillMissingCardImages(List<TcgCatalogCard> cards) {
    for (var i = 0; i < cards.length; i++) {
      cards[i] = _ensureCardImage(cards[i]);
    }
  }

  static TcgCatalogCard _ensureCardImage(TcgCatalogCard card) {
    if (card.imageUrl != null && card.imageUrl!.isNotEmpty) return card;
    final lang = card.raw['card_lang'] ?? PokemonCardLang.fr;
    final primary = tcgdexCardImageUrl(
      card.id,
      localId: card.number,
      lang: lang,
    );
    if (primary != null) {
      return TcgCatalogCard(
        id: card.id,
        name: card.name,
        imageUrl: primary,
        setName: card.setName,
        number: card.number,
        rarity: card.rarity,
        raw: card.raw,
      );
    }
    for (final fallback in PokemonCardLang.all) {
      if (fallback == lang) continue;
      final url = tcgdexCardImageUrl(
        card.id,
        localId: card.number,
        lang: fallback,
      );
      if (url != null) {
        return TcgCatalogCard(
          id: card.id,
          name: card.name,
          imageUrl: url,
          setName: card.setName,
          number: card.number,
          rarity: card.rarity,
          raw: card.raw,
        );
      }
    }
    return card;
  }

  static Future<void> enrichSearchMetadata(
    List<TcgCatalogCard> cards, {
    String lang = PokemonCardLang.fr,
  }) async {
    final setIds = cards
        .map((c) => c.raw['set_id'] ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (setIds.isEmpty) return;

    final cache = <String, Map<String, String>>{};
    for (final setId in setIds) {
      try {
        final cardLang =
            cards.firstWhere((c) => c.raw['set_id'] == setId).raw['card_lang'] ??
                lang;
        final response = await http.get(_uri(cardLang, '/sets/$setId'));
        if (response.statusCode != 200) continue;
        final s = jsonDecode(response.body) as Map<String, dynamic>;
        final serie = s['serie'] as Map<String, dynamic>?;
        final cardCount = s['cardCount'] as Map<String, dynamic>?;
        final total =
            cardCount?['official'] as int? ?? cardCount?['total'] as int?;
        cache[setId] = {
          'set_name': s['name']?.toString() ?? '',
          'block_name': serie?['name']?.toString() ?? '',
          'series_name': serie?['name']?.toString() ?? '',
          if (total != null && total > 0) 'set_total': total.toString(),
        };
      } catch (_) {}
    }

    for (var i = 0; i < cards.length; i++) {
      final c = cards[i];
      final setId = c.raw['set_id'] ?? '';
      final meta = cache[setId];
      if (meta == null) continue;
      cards[i] = TcgCatalogCard(
        id: c.id,
        name: c.name,
        imageUrl: c.imageUrl,
        setName: meta['set_name'] ?? c.setName,
        number: c.number,
        rarity: c.rarity,
        raw: {...c.raw, ...meta},
      );
    }
  }

  static Future<void> enrichCardDetails(List<TcgCatalogCard> cards) async {
    fillMissingCardImages(cards);
    await enrichRarities(cards);
    final stillMissing = cards
        .where((c) => c.imageUrl == null || c.imageUrl!.isEmpty)
        .toList();
    if (stillMissing.isEmpty) return;
    for (final chunk in _chunks(stillMissing, _rarityBatch)) {
      final details = await Future.wait(
        chunk.map(
          (card) => _fetchCardById(
            card.id,
            lang: card.raw['card_lang'] ?? PokemonCardLang.fr,
          ),
        ),
      );
      for (var i = 0; i < chunk.length; i++) {
        final d = details[i];
        if (d?.imageUrl == null || d!.imageUrl!.isEmpty) continue;
        final idx = cards.indexWhere((c) => c.id == chunk[i].id);
        if (idx < 0) continue;
        final old = cards[idx];
        cards[idx] = TcgCatalogCard(
          id: old.id,
          name: old.name,
          imageUrl: d.imageUrl,
          setName: old.setName ?? d.setName,
          number: old.number,
          rarity: old.rarity ?? d.rarity,
          raw: {...old.raw, ...d.raw},
        );
      }
    }
  }

  static Future<void> enrichRarities(List<TcgCatalogCard> cards) async {
    final missing = cards.where((c) => c.rarity == null || c.rarity!.isEmpty);
    for (final chunk in _chunks(missing.toList(), _rarityBatch)) {
      final details = await Future.wait(
        chunk.map(
          (card) => _fetchCardById(
            card.id,
            lang: card.raw['card_lang'] ?? PokemonCardLang.fr,
          ),
        ),
      );
      for (var i = 0; i < chunk.length; i++) {
        final d = details[i];
        if (d?.rarity == null || d!.rarity!.isEmpty) continue;
        final idx = cards.indexWhere((c) => c.id == chunk[i].id);
        if (idx < 0) continue;
        final old = cards[idx];
        cards[idx] = TcgCatalogCard(
          id: old.id,
          name: old.name,
          imageUrl: old.imageUrl ?? d.imageUrl,
          setName: old.setName,
          number: old.number,
          rarity: d.rarity,
          raw: {...old.raw, if (d.rarity != null) 'rarity': d.rarity!},
        );
      }
    }
  }

  static Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.skip(i).take(size).toList();
    }
  }

  static Future<TcgCatalogCard?> _fetchCardById(
    String id, {
    String lang = PokemonCardLang.fr,
  }) async {
    try {
      final response = await http.get(_uri(lang, '/cards/$id'));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _mapCatalogFull(data, lang: lang);
    } catch (e) {
      if (kDebugMode) debugPrint('TCGdex card $id ($lang): $e');
      return null;
    }
  }

  static Future<List<Map<String, String>>> search(
    String query, {
    String lang = PokemonCardLang.fr,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final perLang = await Future.wait(
        PokemonCardLang.all.map((l) => _searchSingleLang(q, lang: l)),
      );

      final merged = <String, Map<String, String>>{};
      for (final list in perLang) {
        for (final hit in list) {
          final tcgdexId = hit['tcgdex_id'] ?? '';
          final cardLang = hit['card_lang'] ?? PokemonCardLang.fr;
          if (tcgdexId.isEmpty) continue;
          merged[PokemonCardLang.catalogKey(tcgdexId, lang: cardLang)] = hit;
        }
      }

      final ids = merged.values
          .map((h) => h['tcgdex_id'])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .take(25);

      for (final id in ids) {
        for (final l in PokemonCardLang.all) {
          final key = PokemonCardLang.catalogKey(id, lang: l);
          if (merged.containsKey(key)) continue;
          final card = await _fetchCardById(id, lang: l);
          if (card == null) continue;
          final enriched = _ensureCardImage(card);
          merged[key] = {
            'title': enriched.name,
            'image_url': enriched.imageUrl ?? '',
            ...enriched.raw,
          };
        }
      }

      return merged.values.toList();
    } catch (e) {
      if (kDebugMode) debugPrint('TCGdex search: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> _searchSingleLang(
    String q, {
    required String lang,
  }) async {
    try {
      final hits = <Map<String, String>>[];

      for (var page = 1; page <= _searchMaxPages; page++) {
        final response = await http.get(_uri(lang, '/cards', {
          'name': q,
          'pagination:page': page.toString(),
          'pagination:itemsPerPage': _searchPageSize.toString(),
          'sort:field': 'name',
          'sort:order': 'ASC',
        }));
        if (response.statusCode != 200) break;

        final list = jsonDecode(response.body) as List<dynamic>;
        if (list.isEmpty) break;

        for (final raw in list) {
          final map = raw as Map<String, dynamic>;
          final id = map['id']?.toString() ?? '';
          final card = _mapCatalogBrief(
            map,
            _setIdFromCardId(id),
            lang: lang,
          );
          if (card == null) continue;
          final enriched = _ensureCardImage(card);
          hits.add({
            'title': enriched.name,
            'image_url': enriched.imageUrl ?? '',
            ...enriched.raw,
          });
        }

        if (list.length < _searchPageSize) break;
      }

      return hits;
    } catch (e) {
      if (kDebugMode) debugPrint('TCGdex search ($lang): $e');
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
    String setId, {
    String lang = PokemonCardLang.fr,
    TcgSetInfo? setInfo,
  }) {
    final name = card['name'] as String?;
    if (name == null || name.isEmpty) return null;

    final id = card['id']?.toString() ?? '';
    final setName = setInfo?.displayName ?? '';
    return TcgCatalogCard(
      id: id,
      name: name,
      imageUrl: _imageUrl(card['image']) ??
          tcgdexCardImageUrl(
            id,
            localId: card['localId']?.toString(),
            lang: lang,
          ),
      setName: setName.isNotEmpty ? setName : null,
      number: card['localId']?.toString(),
      rarity: card['rarity']?.toString(),
      raw: _rawMeta(
        id,
        lang: lang,
        setId: setId,
        setName: setName,
        setCode: setInfo?.code,
        blockName: setInfo?.seriesName,
        setTotal: setInfo?.totalCards,
        number: card['localId']?.toString(),
        rarity: card['rarity']?.toString(),
        types: _typesList(card['types']),
      ),
    );
  }

  static TcgCatalogCard? _mapCatalogFull(
    Map<String, dynamic> card, {
    String lang = PokemonCardLang.fr,
  }) {
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
        lang: lang,
        setId: setId,
        setName: set?['name']?.toString() ?? '',
        setCode: abbr?['official']?.toString(),
        blockName: set?['serie']?['name']?.toString(),
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
    required String lang,
    required String setId,
    String setName = '',
    String? setCode,
    String? blockName,
    int? setTotal,
    String? number,
    String? rarity,
    List<String> types = const [],
  }) {
    return {
      'tcgdex_id': id,
      'pokemon_tcg_id': id,
      'card_lang': lang,
      'set_id': setId,
      if (setCode != null && setCode.isNotEmpty) 'set_code': setCode,
      if (setName.isNotEmpty) 'set_name': setName,
      if (blockName != null && blockName.isNotEmpty) 'block_name': blockName,
      if (blockName != null && blockName.isNotEmpty) 'series_name': blockName,
      if (setTotal != null && setTotal > 0) 'set_total': setTotal.toString(),
      if (number != null && number.isNotEmpty) 'card_number': number,
      if (rarity != null && rarity.isNotEmpty) 'rarity': rarity,
      if (types.isNotEmpty) 'types': types.join(','),
      'source': 'tcgdex',
    };
  }
}
