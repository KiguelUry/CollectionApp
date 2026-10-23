import 'package:collection_app/models/book_subcategory.dart';
import 'package:collection_app/utils/book_series_normalizer.dart';
import 'package:collection_app/utils/book_title_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookTitleParser', () {
    test('extrait série + tome (tiret, T., Vol.)', () {
      final cases = <String, (String, int)>{
        'Thorgal - Tome 16': ('Thorgal', 16),
        'Thorgal - Tome 2': ('Thorgal', 2),
        'Thorgal T.2': ('Thorgal', 2),
        'Naruto - Tome 16': ('Naruto', 16),
        'Kagurabachi - Tome 1': ('Kagurabachi', 1),
        'One Piece Vol. 12': ('One Piece', 12),
        'Astérix - Tome 40': ('Astérix', 40),
      };
      for (final e in cases.entries) {
        final p = BookTitleParser.parse(e.key);
        expect(p.hasSeries, isTrue, reason: e.key);
        expect(p.seriesName, e.value.$1, reason: e.key);
        expect(p.volumeNumber?.round(), e.value.$2, reason: e.key);
      }
    });

    test('titre sans tome → pas de série parsée', () {
      final p = BookTitleParser.parse('La jeune fille à la perle');
      expect(p.hasVolume, isFalse);
      expect(p.hasSeries, isFalse);
    });
  });

  group('BookSeriesNormalizer', () {
    test('compteurs connus', () {
      expect(
        BookSeriesNormalizer.expectedCount('Thorgal', BookSubcategory.comic),
        42,
      );
      expect(
        BookSeriesNormalizer.expectedCount('Naruto', BookSubcategory.manga),
        72,
      );
      expect(
        BookSeriesNormalizer.expectedCount('One Piece', BookSubcategory.manga),
        110,
      );
      expect(
        BookSeriesNormalizer.expectedCount('Kagurabachi', BookSubcategory.manga),
        11,
      );
    });

    test('Thorgal / Astérix → catégorie BD', () {
      expect(
        BookSeriesNormalizer.preferredSubcategory('Thorgal'),
        BookSubcategory.comic,
      );
      expect(
        BookSeriesNormalizer.preferredSubcategory('Les Mondes de Thorgal'),
        BookSubcategory.comic,
      );
      expect(
        BookSeriesNormalizer.preferredSubcategory('Astérix'),
        BookSubcategory.comic,
      );
      expect(
        BookSeriesNormalizer.preferredSubcategory('Naruto'),
        BookSubcategory.manga,
      );
    });

    test('mergeKey ignore le tome', () {
      expect(
        BookSeriesNormalizer.mergeKey('Thorgal - Tome 16'),
        BookSeriesNormalizer.mergeKey('Thorgal'),
      );
    });

    test('displaySeriesName retire le tome', () {
      expect(
        BookSeriesNormalizer.displaySeriesName('Thorgal - Tome 17'),
        'Thorgal',
      );
      expect(
        BookSeriesNormalizer.displaySeriesName('Naruto - Tome 16'),
        'Naruto',
      );
    });

    test('namesMatch ignore casse et tirets', () {
      expect(
        BookSeriesNormalizer.namesMatch('Thorgal', 'thorgal'),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.namesMatch('One Piece', 'one piece'),
        isTrue,
      );
    });
  });
}
