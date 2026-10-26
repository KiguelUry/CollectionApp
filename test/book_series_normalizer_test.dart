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

    test('match strict du n° de tome (1 ≠ 16)', () {
      expect(
        BookTitleParser.titleMatchesVolumeExactly('Naruto - Tome 1', 1),
        isTrue,
      );
      expect(
        BookTitleParser.titleMatchesVolumeExactly('Naruto - Tome 16', 1),
        isFalse,
      );
      expect(
        BookTitleParser.titleMatchesVolumeExactly('Naruto Vol. 16', 1),
        isFalse,
      );
      expect(
        BookTitleParser.titleMatchesVolumeExactly(
          'Thorgal - La Gardienne des clés Tome 17',
          1,
        ),
        isFalse,
      );
      expect(
        BookTitleParser.extractVolumeNumberStrict('Kagurabachi, Vol. 11'),
        11,
      );
    });

    test('VF compacte T10 / T.11 reconnue', () {
      final t10 = BookTitleParser.parse('Kagurabachi T10');
      expect(t10.seriesName, 'Kagurabachi');
      expect(t10.volumeNumber?.round(), 10);
      final t11 = BookTitleParser.parse('Kagurabachi T.11');
      expect(t11.volumeNumber?.round(), 11);
      expect(
        BookTitleParser.titleMatchesVolumeExactly('Kagurabachi T10', 10),
        isTrue,
      );
      expect(
        BookTitleParser.titleMatchesVolumeExactly('Kagurabachi T10', 1),
        isFalse,
      );
      expect(
        BookTitleParser.extractVolumeNumberStrict('Kagurabachi T11'),
        11,
      );
    });
  });

  group('BookSeriesNormalizer', () {
    test('expectedCount / preferredSubcategory toujours null (plus de dicos)', () {
      expect(
        BookSeriesNormalizer.expectedCount('Thorgal', BookSubcategory.comic),
        isNull,
      );
      expect(
        BookSeriesNormalizer.expectedCount('Naruto', BookSubcategory.manga),
        isNull,
      );
      expect(
        BookSeriesNormalizer.expectedCount('One Piece', BookSubcategory.manga),
        isNull,
      );
      expect(
        BookSeriesNormalizer.expectedCount('Kingdom', BookSubcategory.manga),
        isNull,
      );
      expect(BookSeriesNormalizer.preferredSubcategory('Thorgal'), isNull);
      expect(BookSeriesNormalizer.preferredSubcategory('Naruto'), isNull);
      expect(BookSeriesNormalizer.preferredSubcategory('Astérix'), isNull);
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

    test('stripOrphanVolumeSuffix retire « - Tome » sans numéro', () {
      expect(
        BookSeriesNormalizer.stripOrphanVolumeSuffix('Thorgal - Tome'),
        'Thorgal',
      );
      expect(
        BookSeriesNormalizer.stripOrphanVolumeSuffix('Thorgal - Vol'),
        'Thorgal',
      );
      expect(
        BookSeriesNormalizer.displaySeriesName('Thorgal - Tome'),
        'Thorgal',
      );
      expect(
        BookSeriesNormalizer.mergeKey('Kingdom - Tome'),
        BookSeriesNormalizer.mergeKey('Kingdom'),
      );
    });

    test('detectSubcategory depuis éditeur / subjects uniquement', () {
      expect(
        BookSeriesNormalizer.detectSubcategory(seriesName: 'Kingdom'),
        isNull, // plus de liste de titres
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(seriesName: 'Thorgal'),
        isNull,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Kana'),
        BookSubcategory.manga,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Meian'),
        BookSubcategory.manga,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Ototo'),
        BookSubcategory.manga,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Le Lombard'),
        BookSubcategory.comic,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Bamboo'),
        BookSubcategory.comic,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Urban Comics'),
        BookSubcategory.comics,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Panini Comics'),
        BookSubcategory.comics,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(
          subjects: 'Comics & Graphic Novels / Manga',
        ),
        BookSubcategory.manga,
      );
      expect(
        BookSeriesNormalizer.coverSearchSeriesName(
          'One Piece - Édition originale',
        ),
        'One Piece',
      );
    });

    test('looksLikeChapterOrScan distingue chapitres et tomes', () {
      expect(
        BookSeriesNormalizer.looksLikeChapterOrScan(
          'One Piece édition originale - Chapitre 1114',
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.looksLikeChapterOrScan('One Piece - Tome 2'),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.looksLikeChapterOrScan('One Piece Chapter 500'),
        isTrue,
      );
    });

    test('maxVolumeAmongHits respecte (série, auteur)', () {
      final max = BookSeriesNormalizer.maxVolumeAmongHits(
        hits: [
          (title: 'Kingdom - Tome 2', author: 'Yasuhisa Hara', volume: 2),
          (title: 'Kingdom - Tome 10', author: 'Yasuhisa Hara', volume: 10),
          (title: 'TYRAN', author: 'T.M. Frazier', volume: 2),
          (
            title: 'Kingdom - Chapitre 50',
            author: 'Yasuhisa Hara',
            volume: 50,
          ),
        ],
        seriesName: 'Kingdom',
        author: 'Yasuhisa Hara',
      );
      expect(max, 10);
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

    test('hitBelongsToSeries rejette les faux Kingdom', () {
      expect(
        BookSeriesNormalizer.hitBelongsToSeries(
          'Kingdom - Tome 2',
          'Kingdom',
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.hitBelongsToSeries('TYRAN', 'Kingdom'),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.hitBelongsToSeries(
          'How a Realist Hero Rebuilt the Kingdom Vol. 5',
          'Kingdom',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.hitBelongsToSeries(
          'Fallen Kingdom 1: Gestohlenes Erbe',
          'Kingdom',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.hitBelongsToSeries(
          'The Kingdoms of Ruin Vol. 9',
          'Kingdom',
        ),
        isFalse,
      );
    });

    test('authorsMatch compare dynamiquement sans dictionnaire', () {
      expect(
        BookSeriesNormalizer.authorsMatch('Yasuhisa Hara', 'Hara'),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.authorsMatch('Yasuhisa Hara', 'T.M. Frazier'),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.authorMatchesExpected(
          'T.M. Frazier',
          'Yasuhisa Hara',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.authorMatchesExpected('T.M. Frazier', null),
        isTrue, // pas d'auteur attendu → pas de filtre
      );
    });

    test('seriesAuthorKey différencie les homonymes', () {
      expect(
        BookSeriesNormalizer.seriesAuthorKey('Kingdom', 'Yasuhisa Hara'),
        isNot(
          BookSeriesNormalizer.seriesAuthorKey('Kingdom', 'T.M. Frazier'),
        ),
      );
    });

    test('seriesSubcategoryKey fusionne auteurs, sépare Manga/Roman', () {
      expect(
        BookSeriesNormalizer.seriesSubcategoryKey(
          'Boruto - Naruto next generations',
          BookSubcategory.manga,
        ),
        BookSeriesNormalizer.seriesSubcategoryKey(
          'Boruto - Naruto next generations',
          BookSubcategory.manga,
        ),
      );
      expect(
        BookSeriesNormalizer.seriesSubcategoryKey(
          'Kingdom',
          BookSubcategory.manga,
        ),
        isNot(
          BookSeriesNormalizer.seriesSubcategoryKey(
            'Kingdom',
            BookSubcategory.novel,
          ),
        ),
      );
    });

    test('googleBooksCoverQuery injecte intitle et inauthor', () {
      final q = BookSeriesNormalizer.googleBooksCoverQuery(
        seriesTitle: 'Kingdom',
        volumeNumber: 2,
        author: 'Yasuhisa Hara',
      );
      expect(q, contains('intitle:"Kingdom"'));
      expect(q, contains('intitle:"Tome 2"'));
      expect(q, contains('inauthor:"Yasuhisa Hara"'));
    });

    test('parseCatalogSearchQuery sépare titre + tome', () {
      final a = BookSeriesNormalizer.parseCatalogSearchQuery('kingdom 2');
      expect(a.seriesQuery.toLowerCase(), 'kingdom');
      expect(a.volumeNumber, 2);
      final b = BookSeriesNormalizer.parseCatalogSearchQuery('one piece 15');
      expect(b.seriesQuery.toLowerCase(), 'one piece');
      expect(b.volumeNumber, 15);
      final c = BookSeriesNormalizer.parseCatalogSearchQuery(
        'One Piece - Édition originale',
      );
      expect(c.seriesQuery, 'One Piece');
      expect(c.volumeNumber, isNull);
    });

    test('stripEditionSuffix → One Piece sans édition originale', () {
      expect(
        BookSeriesNormalizer.displaySeriesName('One Piece - Édition originale'),
        'One Piece',
      );
      expect(
        BookSeriesNormalizer.stripEditionSuffix(
          'One Piece – Édition originale',
        ),
        'One Piece',
      );
    });

    test('looksLikeChapterOrScan détecte épisode / chapitre', () {
      expect(
        BookSeriesNormalizer.looksLikeChapterOrScan(
          'One Piece - Chapitre 1114',
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.looksLikeChapterOrScan('One Piece Episode 100'),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.looksLikeChapterOrScan('One Piece - Tome 5'),
        isFalse,
      );
    });
  });
}
