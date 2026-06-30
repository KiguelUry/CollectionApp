import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_env.dart';
import '../config/supabase_public_config.dart';
import '../models/tcg_set_info.dart';

/// RiftScribe — Riftbound TCG (API publique, sans clé).
/// Sur le web : proxy Supabase `riftscribe-proxy` (CORS).
/// https://riftscribe.gg/api-docs
class RiftscribeService {
  static const _base = 'https://riftscribe.gg';

  static bool get _useWebProxy => kIsWeb;

  static Map<String, String> get _jsonHeaders => {
        'Accept': 'application/json',
        if (_useWebProxy) ...{
          'Authorization': 'Bearer ${AppEnv.supabaseAnonKey}',
          'apikey': AppEnv.supabaseAnonKey,
        },
      };

  static Uri _uri(String path, Map<String, String> query) {
    if (_useWebProxy) {
      final base = SupabasePublicConfig.url.replaceAll(RegExp(r'/+$'), '');
      return Uri.parse('$base/functions/v1/riftscribe-proxy').replace(
        queryParameters: {
          'path': path,
          ...query,
          'apikey': AppEnv.supabaseAnonKey,
        },
      );
    }
    return Uri.parse('$_base$path').replace(queryParameters: query);
  }

  static Future<http.Response> _get(
    String path,
    Map<String, String> query,
  ) =>
      http.get(_uri(path, query), headers: _jsonHeaders);

  static const _setNames = <String, String>{
    'OGN': 'Origins',
    'SFD': 'Spiritforged',
    'OGS': 'Proving Grounds',
    'UNL': 'Unleashed',
    'VEN': 'Vengeance',
  };

  static const _setOrder = ['VEN', 'SFD', 'OGN', 'OGS', 'UNL'];

  static Future<List<TcgSeriesBlock>> fetchBlocks() async {
    final setIds = await _fetchSetIds();
    if (setIds.isEmpty) return [];

    final main = <TcgSetInfo>[];
    final extra = <TcgSetInfo>[];

    for (final id in setIds) {
      final upper = id.toUpperCase();
      final info = TcgSetInfo(
        id: upper,
        name: _setNames[upper] ?? upper,
        code: upper,
        seriesName: _isStarterOrPromo(upper) ? 'Starters & promos' : 'Extensions',
      );
      if (_isStarterOrPromo(upper)) {
        extra.add(info);
      } else {
        main.add(info);
      }
    }

    void sortSets(List<TcgSetInfo> list) {
      list.sort((a, b) {
        final ia = _setOrder.indexOf(a.code ?? '');
        final ib = _setOrder.indexOf(b.code ?? '');
        if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
        if (ia >= 0) return -1;
        if (ib >= 0) return 1;
        return (a.code ?? '').compareTo(b.code ?? '');
      });
    }

    sortSets(main);
    sortSets(extra);

    await _enrichSetCovers([...main, ...extra]);

    return [
      if (main.isNotEmpty)
        TcgSeriesBlock(
          id: 'main',
          name: 'Extensions',
          nameFr: 'Extensions',
          sets: main,
        ),
      if (extra.isNotEmpty)
        TcgSeriesBlock(
          id: 'extra',
          name: 'Starters & promos',
          nameFr: 'Starters & promos',
          sets: extra,
        ),
    ];
  }

  static bool _isStarterOrPromo(String setId) =>
      setId == 'OGS' || setId == 'UNL';

  static Future<List<String>> _fetchSetIds() async {
    try {
      final response = await _get('/api/cards/filters', {});
      if (response.statusCode != 200) return _setOrder;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final sets = data['sets'] as List<dynamic>? ?? [];
      return sets.map((s) => s.toString().toUpperCase()).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('RiftScribe filters: $e');
      return _setOrder;
    }
  }

  static Future<void> _enrichSetCovers(List<TcgSetInfo> sets) async {
    for (var i = 0; i < sets.length; i++) {
      final set = sets[i];
      final cards = await fetchCardsInSet(set.id, limit: 1);
      final cover = cards.isNotEmpty ? cards.first.imageUrl : null;
      if (cover == null || cover.isEmpty) continue;
      sets[i] = TcgSetInfo(
        id: set.id,
        name: set.name,
        nameFr: set.nameFr,
        code: set.code,
        seriesName: set.seriesName,
        imageUrl: cover,
        symbolUrl: set.symbolUrl,
        releaseDate: set.releaseDate,
        totalCards: set.totalCards,
      );
    }
  }

  static Future<List<TcgCatalogCard>> fetchCardsInSet(
    String setId, {
    TcgSetInfo? setInfo,
    int? limit,
  }) async {
    if (setId.isEmpty) return [];
    final all = <TcgCatalogCard>[];
    var offset = 0;
    const pageSize = 100;

    while (true) {
      final pageLimit = limit != null
          ? (limit - all.length).clamp(1, pageSize)
          : pageSize;
      if (pageLimit <= 0) break;

      final batch = await _fetchCardsPage(
        setId: setId,
        limit: pageLimit,
        offset: offset,
        setInfo: setInfo,
      );
      if (batch.isEmpty) break;
      all.addAll(batch);
      if (limit != null && all.length >= limit) break;
      if (batch.length < pageLimit) break;
      offset += batch.length;
    }

    all.sort((a, b) {
      final na = int.tryParse(a.number ?? '') ?? 0;
      final nb = int.tryParse(b.number ?? '') ?? 0;
      return na.compareTo(nb);
    });
    return all;
  }

  static Future<List<TcgCatalogCard>> _fetchCardsPage({
    required String setId,
    required int limit,
    required int offset,
    TcgSetInfo? setInfo,
  }) async {
    try {
      final response = await _get('/api/cards', {
        'set_id': setId.toUpperCase(),
        'limit': '$limit',
        'offset': '$offset',
        'sort': 'default',
      });
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            'RiftScribe cards $setId: HTTP ${response.statusCode} ${response.body}',
          );
        }
        return [];
      }

      final body = jsonDecode(response.body);
      final list = body is List
          ? body
          : (body as Map<String, dynamic>)['items'] as List<dynamic>? ??
              (body)['data'] as List<dynamic>? ??
              [];

      return list
          .map(
            (c) => _mapCatalogCard(
              c as Map<String, dynamic>,
              setInfo: setInfo,
            ),
          )
          .whereType<TcgCatalogCard>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('RiftScribe cards $setId: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final response = await _get('/api/cards/search', {'q': q, 'limit': '24'});
      if (response.statusCode != 200) {
        return _searchFallback(q);
      }

      final body = jsonDecode(response.body);
      final list = body is List
          ? body
          : (body as Map<String, dynamic>)['results'] as List<dynamic>? ??
              (body)['data'] as List<dynamic>? ??
              [];

      return list
          .map((c) => _mapLegacy(c as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('RiftScribe search: $e');
      return _searchFallback(q);
    }
  }

  static Future<List<Map<String, String>>> _searchFallback(String q) async {
    try {
      final response = await _get('/api/cards', {'q': q, 'limit': '24'});
      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body);
      final list = body is List ? body : <dynamic>[];
      return list
          .map((c) => _mapLegacy(c as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static TcgCatalogCard? _mapCatalogCard(
    Map<String, dynamic> card, {
    TcgSetInfo? setInfo,
  }) {
    final name = card['name'] as String?;
    if (name == null || name.isEmpty) return null;

    final id =
        card['id']?.toString() ?? card['card_id']?.toString() ?? '';
    final setId = card['set_id']?.toString().toUpperCase() ?? '';
    final setName = _setNames[setId] ?? setInfo?.displayName ?? setId;
    final blockName = setInfo?.seriesName ??
        (_isStarterOrPromo(setId) ? 'Starters & promos' : 'Extensions');

    final image = card['image']?.toString();
    final thumbs = card['image_thumb'] as Map<String, dynamic>?;
    final imageUrl = image ??
        thumbs?['large']?.toString() ??
        thumbs?['medium']?.toString() ??
        thumbs?['small']?.toString() ??
        card['thumbnail_url']?.toString();

    final variant = card['variant']?.toString() ?? '';
    final displayName = variant.isNotEmpty ? '$name ($variant)' : name;

    return TcgCatalogCard(
      id: id.isNotEmpty ? id : '$setId-${card['collector_number']}',
      name: displayName,
      imageUrl: imageUrl,
      setName: setName.isNotEmpty ? setName : null,
      number: card['collector_number']?.toString(),
      rarity: card['rarity']?.toString(),
      raw: {
        'riftscribe_id': id,
        'set_id': setId,
        'set_code': setId,
        'set_name': setName,
        'block_name': blockName,
        'series_name': blockName,
        'card_number': card['collector_number']?.toString() ?? '',
        'rarity': card['rarity']?.toString() ?? '',
        'faction': card['faction']?.toString() ?? '',
        'type': card['type']?.toString() ?? '',
        'source': 'riftscribe',
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
