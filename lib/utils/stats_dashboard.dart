import '../models/boardgame_play_session.dart';
import '../models/collection_category.dart';
import 'active_categories.dart';
import 'boardgame_display.dart';
import 'boardgame_expansions.dart';
import 'item_copy_units.dart';
import 'wishlist_market_metadata.dart';

/// Objet valorisé ou joué, prêt à afficher dans le dashboard.
class StatsDashboardItem {
  final String id;
  final String title;
  final CollectionCategory category;
  final String? imageUrl;
  final double value;
  final bool isEstimate;
  final int plays;
  final double? ratingScore;

  const StatsDashboardItem({
    required this.id,
    required this.title,
    required this.category,
    this.imageUrl,
    this.value = 0,
    this.isEstimate = false,
    this.plays = 0,
    this.ratingScore,
  });
}

class StatsCategoryBar {
  final CollectionCategory category;
  final int count;
  final double value;

  const StatsCategoryBar({
    required this.category,
    required this.count,
    this.value = 0,
  });
}

/// Agrégats de la vue d'ensemble — calcul pur à partir des lignes Supabase.
class StatsDashboard {
  final int ownedCount;
  final int expansionCount;
  final int wishlistCount;
  final double wishlistValue;
  final int wishlistPricedCount;
  final int boardgameCount;
  final int playedCount;
  final int unplayedCount;
  final int totalPlays;
  final int awayCount;
  final int loanedCount;
  final double purchaseValue;
  final double estimatedValue;
  final int valuedCount;

  /// Somme des prix d'achat renseignés (par exemplaire).
  final double paidTotal;
  final int paidCopies;

  /// Somme des estimations marché BGG (par exemplaire, même si prix payé connu).
  final double marketTotal;
  final int marketCopies;

  /// Sous-ensemble qui a à la fois un prix payé et une estimation marché.
  final double comparablePaid;
  final double comparableMarket;
  final int comparableCopies;
  final List<StatsCategoryBar> categories;
  final List<StatsDashboardItem> topValued;
  final List<StatsDashboardItem> topPlayed;
  final List<StatsDashboardItem> topRated;

  const StatsDashboard({
    this.ownedCount = 0,
    this.expansionCount = 0,
    this.wishlistCount = 0,
    this.wishlistValue = 0,
    this.wishlistPricedCount = 0,
    this.boardgameCount = 0,
    this.playedCount = 0,
    this.unplayedCount = 0,
    this.totalPlays = 0,
    this.awayCount = 0,
    this.loanedCount = 0,
    this.purchaseValue = 0,
    this.estimatedValue = 0,
    this.valuedCount = 0,
    this.paidTotal = 0,
    this.paidCopies = 0,
    this.marketTotal = 0,
    this.marketCopies = 0,
    this.comparablePaid = 0,
    this.comparableMarket = 0,
    this.comparableCopies = 0,
    this.categories = const [],
    this.topValued = const [],
    this.topPlayed = const [],
    this.topRated = const [],
  });

  /// Total valeur (achat sinon estimation marché).
  double get totalValue => purchaseValue + estimatedValue;

  bool get hasValue => valuedCount > 0;

  /// Part des jeux de société joués au moins une fois (0–1).
  double get playedShare =>
      boardgameCount == 0 ? 0 : playedCount / boardgameCount;

  double get unplayedShare =>
      boardgameCount == 0 ? 0 : unplayedCount / boardgameCount;

  static StatsDashboard fromRows(
    Iterable<Map<String, dynamic>> rawRows, {
    required Set<CollectionCategory> active,
    String? meUserId,
    int topLimit = 10,
  }) {
    final rows = ActiveCategories.filterRows(rawRows, active);
    final seen = <String>{};

    var owned = 0;
    var wishlist = 0;
    var wishlistValue = 0.0;
    var wishlistPriced = 0;
    var boardgames = 0;
    var played = 0;
    var totalPlays = 0;
    var away = 0;
    var loaned = 0;
    var purchase = 0.0;
    var estimated = 0.0;
    var valued = 0;
    var paidTotal = 0.0;
    var paidCopies = 0;
    var marketTotal = 0.0;
    var marketCopies = 0;
    var comparablePaid = 0.0;
    var comparableMarket = 0.0;
    var comparableCopies = 0;
    final counts = <CollectionCategory, int>{};
    final values = <CollectionCategory, double>{};
    final boardgameRows = <Map<String, dynamic>>[];
    final valuedItems = <StatsDashboardItem>[];
    final playedItems = <StatsDashboardItem>[];
    final ratedItems = <StatsDashboardItem>[];

    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty && !seen.add(id)) continue;

      final cat = CollectionCategory.fromDbValue(row['category'] as String);
      final meta = _meta(row);
      final isWishlist = row['is_wishlist'] as bool? ?? false;
      final isSold = row['is_sold'] as bool? ?? false;
      final isExpansion = row['is_expansion'] as bool? ?? false;
      final qty = (row['quantity'] as num?)?.toInt() ?? 1;
      final purchasePrice = _num(row['purchase_price']);
      final market = cat == CollectionCategory.boardgame
          ? (marketSecondhandPriceFromMetadata(meta) ??
              marketNewPriceMinFromMetadata(meta))
          : null;

      if (isWishlist) {
        wishlist++;
        final est = market ?? purchasePrice;
        if (est != null && est > 0) {
          wishlistValue += est;
          wishlistPriced++;
        }
        continue;
      }
      if (isSold) continue;

      if (cat == CollectionCategory.boardgame) boardgameRows.add(row);
      if (isExpansion) continue;

      owned++;
      counts[cat] = (counts[cat] ?? 0) + 1;

      final title = row['title']?.toString() ?? '';
      final image = row['image_url']?.toString() ??
          meta?['image_url']?.toString();

      double? itemValue;
      var isEstimate = false;
      final copyPrices = copyPurchasePricesFromRow(
        quantity: qty,
        purchasePrice: purchasePrice,
        metadata: meta,
      );
      for (final price in copyPrices) {
        if (market != null && market > 0) {
          marketTotal += market;
          marketCopies++;
        }
        if (price != null && price > 0) {
          paidTotal += price;
          paidCopies++;
          purchase += price;
          itemValue = (itemValue ?? 0) + price;
          if (market != null && market > 0) {
            comparablePaid += price;
            comparableMarket += market;
            comparableCopies++;
          }
        } else if (market != null && market > 0) {
          estimated += market;
          itemValue = (itemValue ?? 0) + market;
          isEstimate = true;
        }
      }
      if (itemValue != null) {
        valued++;
        values[cat] = (values[cat] ?? 0) + itemValue;
        valuedItems.add(
          StatsDashboardItem(
            id: id,
            title: title,
            category: cat,
            imageUrl: image,
            value: itemValue,
            isEstimate: isEstimate,
          ),
        );
      }

      if (_isAway(row, meta, meUserId)) away++;
      if (_isLoaned(row)) loaned++;

      if (cat == CollectionCategory.boardgame) {
        boardgames++;
        final plays = playCountFromRow(row);
        totalPlays += plays;
        if (plays > 0) {
          played++;
          playedItems.add(
            StatsDashboardItem(
              id: id,
              title: title,
              category: cat,
              imageUrl: image,
              plays: plays,
            ),
          );
        }
      }

      final personalRaw = _num(row['rating']);
      // Notes perso et BGG unifiées sur /10 pour le classement « mieux notés ».
      final personalRating = personalRatingOnTen(
        personalRaw,
        metadata: meta is Map<String, dynamic> ? meta : null,
      );
      final communityOnTen = bggRatingOnTen(meta?['bgg_avg_rating']);
      final ratingScore = (personalRating != null && personalRating > 0)
          ? personalRating
          : communityOnTen;
      if (ratingScore != null) {
        ratedItems.add(
          StatsDashboardItem(
            id: id,
            title: title,
            category: cat,
            imageUrl: image,
            ratingScore: ratingScore,
          ),
        );
      }
    }

    valuedItems.sort((a, b) => b.value.compareTo(a.value));
    playedItems.sort((a, b) => b.plays.compareTo(a.plays));
    ratedItems.sort(
      (a, b) => (b.ratingScore ?? 0).compareTo(a.ratingScore ?? 0),
    );

    final bars = [
      for (final e in counts.entries)
        if (e.value > 0)
          StatsCategoryBar(
            category: e.key,
            count: e.value,
            value: values[e.key] ?? 0,
          ),
    ]..sort((a, b) => b.count.compareTo(a.count));

    return StatsDashboard(
      ownedCount: owned,
      expansionCount: countUniqueOwnedExpansions(boardgameRows),
      wishlistCount: wishlist,
      wishlistValue: wishlistValue,
      wishlistPricedCount: wishlistPriced,
      boardgameCount: boardgames,
      playedCount: played,
      unplayedCount: boardgames - played,
      totalPlays: totalPlays,
      awayCount: away,
      loanedCount: loaned,
      purchaseValue: purchase,
      estimatedValue: estimated,
      valuedCount: valued,
      paidTotal: paidTotal,
      paidCopies: paidCopies,
      marketTotal: marketTotal,
      marketCopies: marketCopies,
      comparablePaid: comparablePaid,
      comparableMarket: comparableMarket,
      comparableCopies: comparableCopies,
      categories: bars,
      topValued: valuedItems.take(topLimit).toList(),
      topPlayed: playedItems.take(topLimit).toList(),
      topRated: ratedItems.take(topLimit).toList(),
    );
  }

  /// Nombre de parties : historique détaillé, sinon compteur `games_played`.
  static int playCountFromRow(Map<String, dynamic> row) {
    final sessions = parseBoardgamePlays(_meta(row));
    if (sessions.isNotEmpty) return sessions.length;
    return (row['games_played'] as num?)?.toInt() ?? 0;
  }

  static Map<String, dynamic>? _meta(Map<String, dynamic> row) {
    final raw = row['metadata'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static double? _num(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.replaceAll(',', '.'));
    return null;
  }

  static bool _isLoaned(Map<String, dynamic> row) {
    final id = row['loaned_to_id']?.toString();
    final name = row['loaned_to_name']?.toString().trim();
    return (id != null && id.isNotEmpty) || (name != null && name.isNotEmpty);
  }

  /// Hors de chez moi : prêté, chez un autre membre, ou lieu libre.
  static bool _isAway(
    Map<String, dynamic> row,
    Map<String, dynamic>? meta,
    String? meUserId,
  ) {
    if (_isLoaned(row)) return true;
    final holderUser = row['location_user_id']?.toString();
    if (holderUser != null && holderUser.isNotEmpty) {
      return meUserId != null && holderUser != meUserId;
    }
    final manual = meta?['holder_label']?.toString().trim();
    if (manual == null || manual.isEmpty) return false;
    return manual.toLowerCase() != 'chez moi';
  }
}

/// Coût par partie : prix d'achat (sinon estimation) ÷ nombre de parties.
double? costPerPlay({
  double? purchasePrice,
  double? estimatedValue,
  required int plays,
}) {
  if (plays < 1) return null;
  final base = (purchasePrice != null && purchasePrice > 0)
      ? purchasePrice
      : estimatedValue;
  if (base == null || base <= 0) return null;
  return base / plays;
}

/// « 3,50 € / partie »
String formatCostPerPlay(double value) =>
    '${value.toStringAsFixed(2).replaceAll('.', ',')} € / partie';

/// « 1 234 € » (séparateur de milliers fin, pas de décimales).
String formatEuroAmount(double value) {
  final rounded = value.round();
  final digits = rounded.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('\u202f');
    buf.write(digits[i]);
  }
  return '${rounded < 0 ? '-' : ''}$buf €';
}
