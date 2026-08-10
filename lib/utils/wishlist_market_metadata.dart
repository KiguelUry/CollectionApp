/// Champs metadata pour l'aide à l'achat wishlist (jeux de société).
library;

const kPurchasePriority = 'purchase_priority';
const kBggExpansionCount = 'bgg_expansion_count';
const kMarketSecondhandPrice = 'market_secondhand_price';
const kMarketNewPriceMin = 'market_new_price_min';
const kStoresPrices = 'stores_prices';
const kMarketPriceHistory = 'market_price_history';
const kMarketPricesFetchedAt = 'market_prices_fetched_at';
const kPriceSightings = 'price_sightings';

int purchasePriorityFromMetadata(Map<String, dynamic>? metadata) {
  final raw = metadata?[kPurchasePriority];
  final parsed = raw is int
      ? raw
      : int.tryParse('$raw');
  if (parsed == null || parsed <= 0) return 1;
  return parsed.clamp(1, 3);
}

double? marketSecondhandPriceFromMetadata(Map<String, dynamic>? metadata) {
  return _parseEuro(metadata?[kMarketSecondhandPrice]);
}

double? marketNewPriceMinFromMetadata(Map<String, dynamic>? metadata) {
  return _parseEuro(metadata?[kMarketNewPriceMin]);
}

int? bggExpansionCountFromMetadata(Map<String, dynamic>? metadata) {
  final raw = metadata?[kBggExpansionCount];
  if (raw is int) return raw;
  return int.tryParse('$raw');
}

List<StorePriceEntry> storesPricesFromMetadata(Map<String, dynamic>? metadata) {
  final raw = metadata?[kStoresPrices];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map(StorePriceEntry.fromJson)
      .where((e) => e.priceEur > 0)
      .toList()
    ..sort((a, b) => a.priceEur.compareTo(b.priceEur));
}

List<MarketPriceHistoryPoint> marketHistoryFromMetadata(
  Map<String, dynamic>? metadata,
) {
  final raw = metadata?[kMarketPriceHistory];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map(MarketPriceHistoryPoint.fromJson)
      .where((e) => e.at != null)
      .toList()
    ..sort((a, b) => a.at!.compareTo(b.at!));
}

double? _parseEuro(dynamic raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final cleaned = raw.replaceAll('€', '').replaceAll(',', '.').trim();
    return double.tryParse(cleaned);
  }
  return null;
}

String formatEuroChip(double? value, {bool compact = true}) {
  if (value == null || value <= 0) return '—';
  final rounded = value < 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(0);
  return compact ? '$rounded€' : '${rounded.replaceAll('.0', '')} €';
}

String priorityFlameLabel(int priority) {
  return switch (priority.clamp(1, 3)) {
    1 => '🔥',
    2 => '🔥🔥',
    _ => '🔥🔥🔥',
  };
}

class StorePriceEntry {
  final String label;
  final double priceEur;
  final double? productEur;
  final bool inStock;
  final String? country;
  final String? url;

  const StorePriceEntry({
    required this.label,
    required this.priceEur,
    this.productEur,
    this.inStock = false,
    this.country,
    this.url,
  });

  factory StorePriceEntry.fromJson(Map<dynamic, dynamic> json) {
    return StorePriceEntry(
      label: json['label']?.toString() ?? 'Boutique',
      priceEur: _parseEuro(json['price_eur']) ?? 0,
      productEur: _parseEuro(json['product_eur']),
      inStock: json['in_stock'] == true,
      country: json['country']?.toString(),
      url: json['url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'price_eur': priceEur,
        if (productEur != null) 'product_eur': productEur,
        'in_stock': inStock,
        if (country != null) 'country': country,
        if (url != null) 'url': url,
      };
}

class MarketPriceHistoryPoint {
  final DateTime? at;
  final double? secondhandEur;
  final double? newMinEur;

  const MarketPriceHistoryPoint({
    this.at,
    this.secondhandEur,
    this.newMinEur,
  });

  factory MarketPriceHistoryPoint.fromJson(Map<dynamic, dynamic> json) {
    final atRaw = json['at']?.toString();
    return MarketPriceHistoryPoint(
      at: atRaw == null ? null : DateTime.tryParse(atRaw),
      secondhandEur: _parseEuro(json['secondhand']),
      newMinEur: _parseEuro(json['new_min']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (at != null) 'at': at!.toIso8601String(),
        if (secondhandEur != null) 'secondhand': secondhandEur,
        if (newMinEur != null) 'new_min': newMinEur,
      };
}

Map<String, dynamic> mergeMarketMetadataPatch(
  Map<String, dynamic>? existing,
  Map<String, dynamic> patch,
) {
  final merged = Map<String, dynamic>.from(existing ?? {});
  merged.addAll(patch);
  return merged;
}

/// Observation manuelle : « Vu à X € chez [lieu] » (+ URL / photo optionnels).
class PriceSighting {
  final String id;
  final double priceEur;
  final String place;
  final String? url;
  final String? photoUrl;
  final DateTime? seenAt;

  const PriceSighting({
    required this.id,
    required this.priceEur,
    required this.place,
    this.url,
    this.photoUrl,
    this.seenAt,
  });

  factory PriceSighting.fromJson(Map<dynamic, dynamic> json) {
    final atRaw = json['seen_at']?.toString();
    return PriceSighting(
      id: json['id']?.toString() ??
          '${json['place']}_${json['price_eur']}_${atRaw ?? ''}',
      priceEur: _parseEuro(json['price_eur']) ?? 0,
      place: json['place']?.toString() ?? '',
      url: json['url']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      seenAt: atRaw == null ? null : DateTime.tryParse(atRaw),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'price_eur': priceEur,
        'place': place,
        if (url != null && url!.trim().isNotEmpty) 'url': url!.trim(),
        if (photoUrl != null && photoUrl!.trim().isNotEmpty)
          'photo_url': photoUrl!.trim(),
        if (seenAt != null) 'seen_at': seenAt!.toIso8601String(),
      };
}

List<PriceSighting> priceSightingsFromMetadata(Map<String, dynamic>? metadata) {
  final raw = metadata?[kPriceSightings];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map(PriceSighting.fromJson)
      .where((e) => e.priceEur > 0 && e.place.trim().isNotEmpty)
      .toList()
    ..sort((a, b) {
      final aAt = a.seenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.seenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
}

Map<String, dynamic> metadataWithPriceSightings(
  Map<String, dynamic>? existing,
  List<PriceSighting> sightings,
) {
  final meta = Map<String, dynamic>.from(existing ?? {});
  if (sightings.isEmpty) {
    meta.remove(kPriceSightings);
  } else {
    meta[kPriceSightings] = sightings.map((e) => e.toJson()).toList();
  }
  return meta;
}
