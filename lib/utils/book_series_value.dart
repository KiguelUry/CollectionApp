import '../models/book_subcategory.dart';
import '../models/book_series.dart';
import '../models/book_volume.dart';
import '../models/collection_item.dart';

/// Barème indicatif FR par catégorie (modifiable via purchasePrice tome).
abstract final class BookSeriesValue {
  static const mangaStandard = 7.20;
  static const mangaDeluxe = 10.90;
  static const mangaCollector = 14.90;
  static const bdAlbum = 13.50;
  static const comicsStandard = 16.50;
  static const comicsOmnibus = 35.00;
  static const novelPoche = 8.90;
  static const novelGrandFormat = 19.50;
  static const secondhandRatio = 0.60;

  static final _deluxeRe = RegExp(
    r'\b(perfect|deluxe|int[eé]grale|prestige|master\s*edition)\b',
    caseSensitive: false,
  );
  static final _collectorRe = RegExp(
    r'\bcollector\b',
    caseSensitive: false,
  );
  static final _omnibusRe = RegExp(
    r'\b(int[eé]grale|omnibus)\b',
    caseSensitive: false,
  );
  static final _pocheRe = RegExp(
    r'\b(poche|j.?ai\s*lu|pocket|folio)\b',
    caseSensitive: false,
  );

  /// Prix unitaire estimé d'un tome (purchasePrice > barème).
  static double unitPriceFor({
    required BookSubcategory subcategory,
    required String seriesName,
    BookVolume? volume,
    CollectionItem? item,
  }) {
    final paid = item?.purchasePrice;
    if (paid != null && paid > 0) return paid;
    final blob =
        '${volume?.volumeTitle ?? ''} $seriesName ${volume?.metadata['edition'] ?? ''}';
    switch (subcategory) {
      case BookSubcategory.manga:
        if (_collectorRe.hasMatch(blob)) return mangaCollector;
        if (_deluxeRe.hasMatch(blob)) return mangaDeluxe;
        return mangaStandard;
      case BookSubcategory.bd:
        return bdAlbum;
      case BookSubcategory.comics:
        if (_omnibusRe.hasMatch(blob)) return comicsOmnibus;
        return comicsStandard;
      case BookSubcategory.novel:
        if (_pocheRe.hasMatch(blob)) return novelPoche;
        return novelGrandFormat;
      case BookSubcategory.other:
        return novelGrandFormat;
    }
  }

  static BookSeriesValueSummary summarize({
    required BookSeries series,
    required List<BookVolumeSlot> slots,
  }) {
    var ownedValue = 0.0;
    var ownedCount = 0;
    var missingCount = 0;
    var missingValue = 0.0;
    for (final slot in slots) {
      final n = slot.volume.volumeNumber;
      if (n < 0.5) continue; // hors-série / scans
      final owned = slot.status == BookVolumeStatus.owned ||
          (slot.item != null &&
              !slot.item!.isWishlist &&
              !slot.item!.isSold);
      final unit = unitPriceFor(
        subcategory: series.subcategory,
        seriesName: series.name,
        volume: slot.volume,
        item: slot.item,
      );
      if (owned) {
        ownedCount++;
        ownedValue += unit;
      } else {
        missingCount++;
        missingValue += unit;
      }
    }
    return BookSeriesValueSummary(
      ownedCount: ownedCount,
      missingCount: missingCount,
      ownedValueNew: (ownedValue * 10).round() / 10,
      ownedValueUsed: ((ownedValue * secondhandRatio) * 10).round() / 10,
      completeBudget: (missingValue * 10).round() / 10,
    );
  }

  static String fnacSearchUrl(String title) =>
      'https://www.fnac.com/SearchResult/ResultList.aspx?Search=${Uri.encodeQueryComponent(title)}';

  static String culturaSearchUrl(String title) =>
      'https://www.cultura.com/search/results?search_query=${Uri.encodeQueryComponent(title)}';

  static String lirekaSearchUrl(String title) =>
      'https://lireka.com/fr/search?q=${Uri.encodeQueryComponent(title)}';

  static String vintedSearchUrl(String title) =>
      'https://www.vinted.fr/catalog?search_text=${Uri.encodeQueryComponent(title)}';
}

class BookSeriesValueSummary {
  final int ownedCount;
  final int missingCount;
  final double ownedValueNew;
  final double ownedValueUsed;
  final double completeBudget;

  const BookSeriesValueSummary({
    required this.ownedCount,
    required this.missingCount,
    required this.ownedValueNew,
    required this.ownedValueUsed,
    required this.completeBudget,
  });
}
