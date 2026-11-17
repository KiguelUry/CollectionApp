import 'package:collection_app/models/book_series.dart';
import 'package:collection_app/models/book_subcategory.dart';
import 'package:collection_app/models/book_volume.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/services/books_collection_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => BooksCollectionCache.instance.clear());

  test('updateSeries après possédé met à jour ownedCount pour la grille', () {
    final series = BookSeries(
      id: 's1',
      name: 'Dune',
      subcategory: BookSubcategory.novel,
      ownerId: 'u1',
      expectedVolumeCount: 6,
    );
    final volumes = [
      for (var i = 1; i <= 6; i++)
        BookVolume(
          id: 'v$i',
          seriesId: 's1',
          volumeNumber: i.toDouble(),
          sortIndex: i.toDouble(),
          label: 'Tome $i',
        ),
    ];
    const emptyStats = BookSeriesStats(totalSlots: 6);
    BooksCollectionCache.instance.put([
      CachedSeriesEntry(
        series: series,
        volumes: volumes,
        items: const [],
        stats: emptyStats,
      ),
    ]);

    final owned = CollectionItem(
      id: 'i1',
      title: 'Dune T1',
      category: CollectionCategory.book,
      seriesId: 's1',
      volumeId: 'v1',
      isWishlist: false,
      quantity: 1,
      addedBy: 'u1',
    );
    const nextStats = BookSeriesStats(ownedCount: 1, totalSlots: 6);
    BooksCollectionCache.instance.updateSeries(
      seriesId: 's1',
      items: [owned],
      stats: nextStats,
    );

    final hit = BooksCollectionCache.instance.entryFor('s1');
    expect(hit, isNotNull);
    expect(hit!.stats.ownedCount, 1);
    expect(hit.items, hasLength(1));
    expect(hit.stats.ownedCount > 0, isTrue);
  });
}
