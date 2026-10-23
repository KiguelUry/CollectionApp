import '../models/book_series.dart';
import '../models/book_volume.dart';
import '../models/collection_item.dart';

/// Cache mémoire vive de la collection Livres (évite le moulinage à chaque ouverture).
class BooksCollectionCache {
  BooksCollectionCache._();
  static final instance = BooksCollectionCache._();

  List<CachedSeriesEntry>? entries;
  DateTime? loadedAt;

  bool get hasData => entries != null && entries!.isNotEmpty;

  void put(List<CachedSeriesEntry> list) {
    entries = list;
    loadedAt = DateTime.now();
  }

  void clear() {
    entries = null;
    loadedAt = null;
  }

  void updateSeries({
    required String seriesId,
    BookSeries? series,
    List<BookVolume>? volumes,
    List<CollectionItem>? items,
    BookSeriesStats? stats,
  }) {
    final list = entries ?? <CachedSeriesEntry>[];
    entries = list;
    final i = list.indexWhere((e) => e.series.id == seriesId);
    if (i < 0) {
      if (series == null || volumes == null || items == null || stats == null) {
        return;
      }
      list.add(
        CachedSeriesEntry(
          series: series,
          volumes: volumes,
          items: items,
          stats: stats,
        ),
      );
      loadedAt = DateTime.now();
      return;
    }
    final cur = list[i];
    list[i] = CachedSeriesEntry(
      series: series ?? cur.series,
      volumes: volumes ?? cur.volumes,
      items: items ?? cur.items,
      stats: stats ?? cur.stats,
    );
  }
}

class CachedSeriesEntry {
  final BookSeries series;
  final List<BookVolume> volumes;
  final List<CollectionItem> items;
  final BookSeriesStats stats;

  const CachedSeriesEntry({
    required this.series,
    required this.volumes,
    required this.items,
    required this.stats,
  });
}
