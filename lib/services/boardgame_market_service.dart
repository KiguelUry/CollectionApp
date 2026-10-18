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
  static const marketPricesTtl = Duration(hours: 24);
  static const _siteName = 'collectingo.app';
  static const _historyMax = 40;
  static const outlierFloorRatio = 0.45;
  static const secondhandOfMedian = 0.65;
  static const _preferredCountries = {'FR', 'BE', 'NL', 'DE', 'GB', 'ES', 'IT'};

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
      final summary = summarizePositivePrices(
        market.stores.map((s) => s.productEur ?? s.priceEur),
      );
      if (summary != null) {
        patch[kMarketPriceMin] = summary.min;
        patch[kMarketPriceMax] = summary.max;
        patch[kMarketPriceAvg] = summary.avg;
        patch[kMarketNewPriceMin] = summary.min;
        patch[kMarketSecondhandPrice] = summary.secondhand;
      }
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
    if (fetchedAt != null && !cachedPricesNeedRefresh(item.metadata)) {
      final at = DateTime.tryParse(fetchedAt);
      final hasPrices =
          marketSecondhandPriceFromMetadata(item.metadata) != null ||
          marketNewPriceMinFromMetadata(item.metadata) != null;
      if (at != null &&
          hasPrices &&
          DateTime.now().difference(at) < marketPricesTtl) {
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

  /// Enrichit les jeux possédés sans prix marché (tâche de fond, lot limité).
  static Future<int> enrichOwnedBatch(
    Iterable<CollectionItem> items, {
    int maxItems = 10,
  }) async {
    var done = 0;
    for (final item in items) {
      if (done >= maxItems) break;
      if (item.isWishlist || item.isSold) continue;
      final bggId = item.metadata?['bgg_id']?.toString();
      if (bggId == null || bggId.isEmpty) continue;
      final hasPrice =
          !cachedPricesNeedRefresh(item.metadata) &&
          (marketSecondhandPriceFromMetadata(item.metadata) != null ||
              marketNewPriceMinFromMetadata(item.metadata) != null);
      if (hasPrice) continue;
      try {
        await enrichItemMetadata(item);
        done++;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 320));
    }
    return done;
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

    for (final item in items) {
      if (item is! Map) continue;
      final prices = item['prices'];
      if (prices is! List) continue;
      _collectLanguagesFromVersions(item['versions'], languages);

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
        final explicitName = p['name']?.toString().trim();

        final label = _storeLabel(
          country: country,
          lang: _firstLanguageCode(item['versions']),
          url: link,
          explicitName: explicitName,
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

    final summary = summarizePositivePrices(
      uniqueStores.map((s) => s.productEur ?? s.priceEur),
    );
    if (summary == null) return null;
    final floor = summary.median * outlierFloorRatio;
    final kept = uniqueStores
        .where((s) => (s.productEur ?? s.priceEur) + 1e-9 >= floor)
        .toList();

    return _MarketFetchResult(
      newMinEur: summary.min,
      secondhandEstimateEur: summary.secondhand,
      stores: (kept.isEmpty ? uniqueStores : kept).take(12).toList(),
      languages: languages,
    );
  }

  /// Médiane, puis retrait des offres sous 45 % de cette médiane.
  /// L'occasion vaut ~65 % de la médiane des offres gardées.
  static MarketPriceSummary? summarizePositivePrices(Iterable<double> raw) {
    final prices = raw.where((p) => p > 0).toList()..sort();
    if (prices.isEmpty) return null;
    final median = _median(prices);
    final floor = median * outlierFloorRatio;
    final kept = prices.where((p) => p + 1e-9 >= floor).toList();
    final use = kept.isEmpty ? <double>[median] : kept;
    final avg = use.reduce((a, b) => a + b) / use.length;
    final med = _median(use);
    return MarketPriceSummary(
      min: use.first,
      avg: (avg * 10).round() / 10,
      max: use.last,
      median: med,
      secondhand: ((med * secondhandOfMedian) * 10).round() / 10,
    );
  }

  static bool cachedPricesNeedRefresh(Map<String, dynamic>? meta) {
    final summary = summarizePositivePrices(
      storesPricesFromMetadata(meta).map((s) => s.productEur ?? s.priceEur),
    );
    if (summary == null) return false;
    final storedMin = marketPriceMinFromMetadata(meta);
    final storedSecond = marketSecondhandPriceFromMetadata(meta);
    if (storedMin != null && (storedMin - summary.min).abs() > 0.4) {
      return true;
    }
    if (storedSecond != null &&
        (storedSecond - summary.secondhand).abs() > 0.4) {
      return true;
    }
    return false;
  }

  static double _median(List<double> sorted) {
    final n = sorted.length;
    if (n == 0) return 0;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  static String vintedSearchUrl(String title) {
    final q = 'jeu de societe ${title.trim()}'.replaceAll(RegExp(r'\s+'), '+');
    return 'https://www.vinted.be/catalog?search_text=$q';
  }

  static String caseDepartSearchUrl(String title) {
    final q = Uri.encodeQueryComponent('site:casedepart.be ${title.trim()}');
    return 'https://www.google.com/search?q=$q';
  }

  static String zebreAPoisSearchUrl(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[&:;,.!?/\\()\[\]"“”‘’]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return 'https://www.lezap.be/index.php?fc=module&module=leoproductsearch&controller=productsearch&search_query=${Uri.encodeQueryComponent(cleaned)}';
  }

  static String philibertSearchUrl(String title) =>
      'https://www.philibertnet.com/fr/recherche?search_query=${Uri.encodeQueryComponent(title.trim())}';

  static String fnacSearchUrl(String title) =>
      'https://www.fnac.com/SearchResult/ResultList.aspx?Search=${Uri.encodeQueryComponent(title.trim())}';

  static String okkazeoSearchUrl(String title) =>
      'https://www.okkazeo.com/jeux/resultats?rech_nom=${Uri.encodeQueryComponent(title.trim())}';

  static String leboncoinSearchUrl(String title) {
    final q = Uri.encodeQueryComponent(title.trim());
    return 'https://www.leboncoin.fr/recherche?text=$q&category=25';
  }

  static String _storeLabel({
    String? country,
    String? lang,
    String? url,
    String? explicitName,
  }) {
    if (explicitName != null &&
        explicitName.isNotEmpty &&
        explicitName.toLowerCase() != 'null') {
      return explicitName;
    }
    final host = url == null
        ? ''
        : (Uri.tryParse(url)?.host.toLowerCase() ?? '');
    final known = _knownShopName(host);
    if (known != null) return known;
    if (host.isNotEmpty) return _prettyDomain(host);
    if (lang != null && lang.isNotEmpty) return 'Éd. $lang';
    if (country != null && country.isNotEmpty) return 'Offre $country';
    return 'Boutique';
  }

  static String? _knownShopName(String host) {
    if (host.contains('philibert')) return 'Philibert';
    if (host.contains('ludum')) return 'Ludum';
    if (host.contains('amazon')) return 'Amazon';
    if (host.contains('esdevium')) return 'Esdevium';
    if (host.contains('fnac')) return 'Fnac';
    if (host.contains('cultura')) return 'Cultura';
    if (host.contains('fantasy-inspirations')) return 'Fantasy Insp.';
    if (host.contains('casedepart')) return 'Case Départ';
    if (host.contains('lezebreapois')) return 'Le Zèbre à Pois';
    if (host.contains('okkazeo')) return 'Okkazeo';
    if (host.contains('geekdo') || host.contains('boardgamegeek')) {
      return 'GeekMarket';
    }
    return null;
  }

  static String _prettyDomain(String host) {
    var h = host.toLowerCase();
    if (h.startsWith('www.')) h = h.substring(4);
    final parts = h.split('.');
    final base = parts.length >= 2 ? parts[parts.length - 2] : parts.first;
    if (base.isEmpty) return host;
    return base[0].toUpperCase() + base.substring(1);
  }

  static String? _firstLanguageCode(dynamic versions) {
    final langs = <String>{};
    _collectLanguagesFromVersions(versions, langs);
    if (langs.isEmpty) return null;
    return langs.first;
  }

  static void _collectLanguagesFromVersions(
    dynamic versions,
    Set<String> languages,
  ) {
    if (versions is Map) {
      final lang = versions['lang'];
      if (lang is List) {
        for (final l in lang) {
          final code = normalizeBoardgameLanguageCode(l.toString());
          if (code.isNotEmpty) languages.add(code);
        }
      } else if (lang != null) {
        final code = normalizeBoardgameLanguageCode(lang.toString());
        if (code.isNotEmpty) languages.add(code);
      }
      return;
    }
    if (versions is List) {
      for (final v in versions) {
        if (v is Map) _collectLanguagesFromVersions(v, languages);
      }
    }
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
    return withoutToday;
  }
}

class MarketPriceSummary {
  final double min;
  final double avg;
  final double max;
  final double median;
  final double secondhand;

  const MarketPriceSummary({
    required this.min,
    required this.avg,
    required this.max,
    required this.median,
    required this.secondhand,
  });
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
