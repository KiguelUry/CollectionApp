import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_env.dart';
import '../config/supabase_public_config.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/collection_refresh.dart';
import '../utils/wishlist_market_metadata.dart';
import '../utils/boardgame_language.dart';

/// Prix neufs (BoardGamePrices) + estimation occasion + enrichissement metadata.
class BoardgameMarketService {
  static const _siteName = 'collectingo.app';
  static const _historyMax = 40;
  static const _secondhandRatio = 0.52;
  static const _preferredCountries = {'FR', 'BE', 'NL', 'DE', 'GB', 'ES', 'IT'};
  static const _trustedStoreHosts = {
    'philibertnet.com',
    'ludum.fr',
    'amazon.fr',
    'amazon.de',
    'amazon.co.uk',
    'amazon.es',
    'amazon.it',
    'esdevium.com',
    'fantasy-inspirations.com',
    'board-game.co.uk',
    'zavvi.com',
    'fnac.com',
    'cultura.com',
    'jeuxvideoclub.com',
  };

  static bool get _webProxyReady =>
      AppEnv.supabaseUrl.isNotEmpty && AppEnv.supabaseAnonKey.isNotEmpty;

  /// Rafraîchit les champs marché d'un jeu BGG et retourne le patch metadata.
  static Future<Map<String, dynamic>> fetchMarketPatch({
    required String bggId,
    Map<String, dynamic>? existing,
    bool includeExpansionCount = true,
  }) async {
    final patch = <String, dynamic>{};

    if (includeExpansionCount &&
        bggExpansionCountFromMetadata(existing) == null) {
      try {
        final expansions = await BggService.fetchExpansions(bggId);
        patch[kBggExpansionCount] = expansions.length;
      } catch (_) {}
    }

    final market = await _fetchStorePrices(bggId);
    if (market == null) {
      patch[kMarketPricesFetchedAt] = DateTime.now().toIso8601String();
      return patch;
    }

    if (market.newMinEur != null) {
      patch[kMarketNewPriceMin] = market.newMinEur;
    }
    if (market.secondhandEstimateEur != null) {
      patch[kMarketSecondhandPrice] = market.secondhandEstimateEur;
    }
    if (market.stores.isNotEmpty) {
      patch[kStoresPrices] = market.stores.map((e) => e.toJson()).toList();
    }
    if (market.languages.isNotEmpty) {
      patch[kBggLanguages] = market.languages.toList();
    }
    patch[kMarketPricesFetchedAt] = DateTime.now().toIso8601String();

    final history = marketHistoryFromMetadata(existing);
    final nextHistory = _appendHistory(
      history,
      secondhand: market.secondhandEstimateEur,
      newMin: market.newMinEur,
    );
    if (nextHistory.isNotEmpty) {
      patch[kMarketPriceHistory] = nextHistory.map((e) => e.toJson()).toList();
    }

    return patch;
  }

  static Future<void> enrichItemMetadata(CollectionItem item) async {
    final bggId = item.metadata?['bgg_id']?.toString();
    if (bggId == null || bggId.isEmpty) return;

    final fetchedAt = item.metadata?[kMarketPricesFetchedAt]?.toString();
    if (fetchedAt != null) {
      final at = DateTime.tryParse(fetchedAt);
      final hasPrices =
          marketSecondhandPriceFromMetadata(item.metadata) != null ||
          marketNewPriceMinFromMetadata(item.metadata) != null;
      if (at != null &&
          hasPrices &&
          DateTime.now().difference(at).inHours < 20) {
        return;
      }
    }

    final patch = await fetchMarketPatch(bggId: bggId, existing: item.metadata);
    if (patch.isEmpty) return;

    final meta = mergeMarketMetadataPatch(item.metadata, patch);
    await Supabase.instance.client
        .from('collection_items')
        .update({'metadata': meta})
        .eq('id', item.id);
    CollectionRefresh.instance.bump();
  }

  static Future<void> enrichWishlistBatch(
    Iterable<CollectionItem> items,
  ) async {
    for (final item in items) {
      if (!item.isWishlist) continue;
      try {
        await enrichItemMetadata(item);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
  }

  static Future<void> setPurchasePriority(
    CollectionItem item,
    int priority,
  ) async {
    final meta = Map<String, dynamic>.from(item.metadata ?? {});
    final p = priority.clamp(1, 3);
    meta[kPurchasePriority] = p;
    await Supabase.instance.client
        .from('collection_items')
        .update({'metadata': meta})
        .eq('id', item.id);
    CollectionRefresh.instance.bump();
  }

  static Future<_MarketFetchResult?> _fetchStorePrices(String bggId) async {
    try {
      final decoded = kIsWeb && _webProxyReady
          ? await _fetchViaProxy(bggId)
          : await _fetchDirect(bggId);
      if (decoded == null) return null;
      return _parseBoardGamePricesResponse(decoded);
    } catch (e) {
      if (kDebugMode) debugPrint('BoardgameMarketService: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchViaProxy(String bggId) async {
    final base = SupabasePublicConfig.url.replaceAll(RegExp(r'/+$'), '');
    final anon = AppEnv.supabaseAnonKey;
    final uri = Uri.parse('$base/functions/v1/bgg-api').replace(
      queryParameters: {'action': 'prices', 'eid': bggId, 'apikey': anon},
    );
    final res = await http.get(uri, headers: {'apikey': anon});
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static Future<Map<String, dynamic>?> _fetchDirect(String bggId) async {
    final uri = Uri.https('boardgameprices.com', '/api/info', {
      'eid': bggId,
      'currency': 'EUR',
      'destination': 'FR',
      'sitename': _siteName,
      'locale': 'fr',
      'sort': 'CHEAP2',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static _MarketFetchResult? _parseBoardGamePricesResponse(
    Map<String, dynamic> decoded,
  ) {
    final items = decoded['items'];
    if (items is! List || items.isEmpty) return null;

    final stores = <StorePriceEntry>[];
    final languages = <String>{};
    double? minInStock;
    double? minAny;

    for (final item in items) {
      if (item is! Map) continue;
      final prices = item['prices'];
      if (prices is! List) continue;
      final lang = (item['versions'] as Map?)?['lang'];
      if (lang is List) {
        for (final l in lang) {
          final code = normalizeBoardgameLanguageCode(l.toString());
          if (code.isNotEmpty) languages.add(code);
        }
      }

      for (final p in prices) {
        if (p is! Map) continue;
        final product = _toDouble(p['product']);
        final total = _toDouble(p['price']) ?? product;
        if (product == null && total == null) continue;
        final productEur = product ?? total!;
        final totalEur = total ?? productEur;
        final stock = p['stock']?.toString().toUpperCase();
        final inStock = stock == 'Y';
        final country = p['country']?.toString();
        final link = p['link']?.toString();
        if (link != null && link.isNotEmpty && !_isTrustedStore(link)) {
          continue;
        }
        if (country != null &&
            country.isNotEmpty &&
            !_preferredCountries.contains(country)) {
          continue;
        }

        if (inStock) {
          minInStock = minInStock == null
              ? productEur
              : (productEur < minInStock ? productEur : minInStock);
        }
        minAny = minAny == null
            ? productEur
            : (productEur < minAny ? productEur : minAny);

        final label = _storeLabel(
          country: country,
          lang: lang is List && lang.isNotEmpty ? lang.first.toString() : null,
          url: link,
        );
        stores.add(
          StorePriceEntry(
            label: label,
            priceEur: totalEur,
            productEur: productEur,
            inStock: inStock,
            country: country,
            url: link,
          ),
        );
      }
    }

    if (stores.isEmpty) return null;
    stores.sort(
      (a, b) => a.productEur?.compareTo(b.productEur ?? a.priceEur) ?? 0,
    );

    final deduped = <String, StorePriceEntry>{};
    for (final s in stores) {
      final key = '${s.label}_${s.productEur?.toStringAsFixed(2)}';
      deduped.putIfAbsent(key, () => s);
    }
    var uniqueStores = deduped.values.toList()
      ..sort(
        (a, b) =>
            (a.productEur ?? a.priceEur).compareTo(b.productEur ?? b.priceEur),
      );
    final filteredStores = uniqueStores
        .where(
          (s) =>
              s.inStock &&
              s.country != null &&
              _preferredCountries.contains(s.country),
        )
        .toList();
    if (filteredStores.isNotEmpty) {
      uniqueStores = filteredStores;
    }

    final newMin = minInStock ?? minAny;
    final secondhand = newMin != null
        ? (newMin * _secondhandRatio * 10).round() / 10
        : null;

    return _MarketFetchResult(
      newMinEur: newMin,
      secondhandEstimateEur: secondhand,
      stores: uniqueStores.take(12).toList(),
      languages: languages,
    );
  }

  static bool _isTrustedStore(String? url) {
    if (url == null || url.isEmpty) return false;
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    return _trustedStoreHosts.any((h) => host.contains(h));
  }

  static String vintedSearchUrl(String title) {
    // Vinted does not document a stable board-game catalog ID; keep only its
    // public query parameters and never infer listings by scraping.
    return Uri.https('www.vinted.fr', '/catalog', {
      'search_text': title.trim(),
      'order': 'relevance',
    }).toString();
  }

  static String leboncoinSearchUrl(String title) {
    final q = Uri.encodeQueryComponent(title.trim());
    return 'https://www.leboncoin.fr/recherche?text=$q&category=25';
  }

  static String _storeLabel({String? country, String? lang, String? url}) {
    final host = url == null
        ? ''
        : (Uri.tryParse(url)?.host.toLowerCase() ?? '');
    if (host.contains('philibert')) return 'Philibert';
    if (host.contains('ludum')) return 'Ludum';
    if (host.contains('amazon')) return 'Amazon';
    if (host.contains('esdevium')) return 'Esdevium';
    if (host.contains('fnac')) return 'Fnac';
    if (host.contains('cultura')) return 'Cultura';
    if (host.contains('fantasy-inspirations')) return 'Fantasy Insp.';
    if (country == 'FR') return 'Boutique FR';
    if (country == 'BE') return 'Boutique BE';
    if (country == 'DE') return 'Boutique DE';
    if (country == 'GB') return 'Boutique UK';
    if (lang != null && lang.isNotEmpty) return 'Éd. $lang';
    if (country != null && country.isNotEmpty) return 'Offre $country';
    return 'Boutique';
  }

  static double? _toDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw');
  }

  static List<MarketPriceHistoryPoint> _appendHistory(
    List<MarketPriceHistoryPoint> existing, {
    double? secondhand,
    double? newMin,
  }) {
    if (secondhand == null && newMin == null) return existing;
    final today = DateTime.now();
    final dayKey = DateTime(today.year, today.month, today.day);
    final withoutToday = existing.where((p) {
      final at = p.at;
      if (at == null) return true;
      final d = DateTime(at.year, at.month, at.day);
      return d != dayKey;
    }).toList();
    withoutToday.add(
      MarketPriceHistoryPoint(
        at: dayKey,
        secondhandEur: secondhand,
        newMinEur: newMin,
      ),
    );
    if (withoutToday.length > _historyMax) {
      return withoutToday.sublist(withoutToday.length - _historyMax);
    }
    if (withoutToday.length == 1) {
      final only = withoutToday.first;
      final at = only.at ?? dayKey;
      withoutToday.insert(
        0,
        MarketPriceHistoryPoint(
          at: at.subtract(const Duration(days: 6)),
          secondhandEur: only.secondhandEur,
          newMinEur: only.newMinEur,
        ),
      );
    }
    return withoutToday;
  }
}

class _MarketFetchResult {
  final double? newMinEur;
  final double? secondhandEstimateEur;
  final List<StorePriceEntry> stores;
  final Set<String> languages;

  const _MarketFetchResult({
    this.newMinEur,
    this.secondhandEstimateEur,
    required this.stores,
    this.languages = const {},
  });
}
