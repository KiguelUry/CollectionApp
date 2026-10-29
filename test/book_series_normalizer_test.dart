import 'package:collection_app/constants/rating_colors.dart';
import 'package:collection_app/models/book_series.dart';
import 'package:collection_app/models/book_subcategory.dart';
import 'package:collection_app/models/book_volume.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/services/anilist_manga_service.dart';
import 'package:collection_app/services/book_intelligence_service.dart';
import 'package:collection_app/services/google_books_service.dart';
import 'package:collection_app/services/mangadex_service.dart';
import 'package:collection_app/utils/book_series_normalizer.dart';
import 'package:collection_app/utils/book_title_parser.dart';
import 'package:collection_app/utils/book_vf_edition.dart';
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

    test('Tome N au milieu + coupe au premier ":" (romans SEO)', () {
      final t1 = BookTitleParser.parse(
        'Dungeon Crawler Carl - Tome 1 : une aventure de LitRPG. '
        'Saga de science-fiction… Livre nouveauté 2024 (version française)',
      );
      expect(t1.seriesName, 'Dungeon Crawler Carl');
      expect(t1.volumeNumber?.round(), 1);

      final t2 = BookTitleParser.parse(
        "Dungeon Crawler Carl : L'Ogive du jugement dernier - Tome 2 : "
        'une aventure de LitRPG… Livre nouveauté 2025',
      );
      expect(t2.seriesName, 'Dungeon Crawler Carl');
      expect(t2.volumeNumber?.round(), 2);

      final t4 = BookTitleParser.parse(
        'Les sept sœurs - Tome 4 : La sœur à la perle',
      );
      expect(t4.seriesName, 'Les sept sœurs');
      expect(t4.volumeNumber?.round(), 4);

      // Année 2024 ne doit pas être prise pour un n° de tome.
      expect(
        BookTitleParser.extractVolumeNumberStrict(
          'Dungeon Crawler Carl Livre nouveauté 2024',
        ),
        isNull,
      );
    });

    test('Harry Potter : seriesInfo + préfixe à/et', () {
      final p = BookTitleParser.parse(
        "Harry Potter à l'école des sorciers",
        apiVolumeNumber: 1,
        queryHint: 'Harry Potter',
      );
      expect(p.seriesName, 'Harry Potter');
      expect(p.volumeNumber?.round(), 1);

      final p2 = BookTitleParser.parse(
        'Harry Potter et la Chambre des secrets',
        apiVolumeNumber: 2,
        queryHint: 'Harry Potter',
      );
      expect(p2.seriesName, 'Harry Potter');
      expect(p2.volumeNumber?.round(), 2);
    });

    test('Harry Potter : ordre de publication → 7 tomes', () {
      final titles = [
        "Harry Potter à l'école des sorciers",
        'Harry Potter et la Chambre des secrets',
        "Harry Potter et le Prisonnier d'Azkaban",
        'Harry Potter et la Coupe de feu',
        "Harry Potter et l'Ordre du Phénix",
        'Harry Potter et le Prince de sang-mêlé',
        'Harry Potter et les Reliques de la Mort',
      ];
      final years = [
        '1998-10-09',
        '1999-03-23',
        '1999-10-14',
        '2000-11-09',
        '2003-12-03',
        '2005-12-01',
        '2007-10-26',
      ];
      final hits = [
        for (var i = 0; i < titles.length; i++)
          EnrichedBookHit(
            raw: {
              'title': titles[i],
              'author': 'J.K. Rowling',
              'published_date': years[i],
              'source': 'itunes',
              'language': 'fr',
            },
            parsed: BookTitleParser.parse(
              titles[i],
              queryHint: 'Harry Potter',
            ),
            displayTitle: titles[i],
            author: 'J.K. Rowling',
            score: 1,
            detectedSubcategory: BookSubcategory.novel,
          ),
      ];
      final numbered = BookIntelligenceService.assignPublicationOrderVolumes(
        hits,
        queryHint: 'Harry Potter',
      );
      expect(
        BookIntelligenceService.assignPublicationOrderVolumes(
          [
            EnrichedBookHit(
              raw: {
                'title': 'Kagurabachi - Tome 6',
                'source': 'google_books',
              },
              parsed: BookTitleParser.parse('Kagurabachi - Tome 6'),
              displayTitle: 'Kagurabachi - Tome 6',
              score: 1,
              detectedSubcategory: BookSubcategory.manga,
            ),
            EnrichedBookHit(
              raw: {
                'title': 'Kagurabachi - Tome 3',
                'source': 'google_books',
              },
              parsed: BookTitleParser.parse('Kagurabachi - Tome 3'),
              displayTitle: 'Kagurabachi - Tome 3',
              score: 1,
              detectedSubcategory: BookSubcategory.manga,
            ),
          ],
          queryHint: 'Kagurabachi',
        ).map((h) => h.parsed.volumeNumber?.round()).toList(),
        [6, 3],
      );
      expect(
        BookTitleParser.extractVolumeFromProse(
          'Quatrième tome de la saga Les Sept Sœurs.',
        ),
        4,
      );
      expect(
        BookTitleParser.extractVolumeFromProse('The first book in the series.'),
        1,
      );
      expect(BookTitleParser.volumeTrailingSeries('One Piece 12', 'One Piece'), 12);
      expect(BookTitleParser.volumeTrailingSeries('One Piece T01', 'One Piece'), 1);
      expect(
        BookSeriesNormalizer.textMentionsSeries(
          'Collection Les sept sœurs, roman de Lucinda Riley',
          'Les sept sœurs',
        ),
        isTrue,
      );
      final sameDate = BookIntelligenceService.assignPublicationOrderVolumes(
        [
          for (final title in [
            'Harry Potter and the Chamber of Secrets',
            'Harry Potter and the Deathly Hallows',
          ])
            EnrichedBookHit(
              raw: {
                'title': title,
                'author': 'J.K. Rowling',
                'published_date': '2015-01-01',
                'source': 'itunes',
                'language': 'en',
              },
              parsed: BookTitleParser.parse(title, queryHint: 'Harry Potter'),
              displayTitle: title,
              author: 'J.K. Rowling',
              score: 1,
              detectedSubcategory: BookSubcategory.novel,
            ),
        ],
        queryHint: 'Harry Potter',
      );
      expect(
        sameDate.map((h) => h.parsed.volumeNumber).toList(),
        [null, null],
      );
      expect(ratingColor(0).toARGB32(), 0xFF991B1B);
      expect(ratingColor(5).toARGB32(), 0xFF38BDF8);
      expect(numbered.length, 7);
      expect(
        numbered.map((h) => h.parsed.volumeNumber?.round()).toList(),
        [1, 2, 3, 4, 5, 6, 7],
      );
    });

    test('Intégrale numérotée reste une série distincte', () {
      final p = BookTitleParser.parse('Walking Dead - Intégrale - Tome 25');
      expect(p.seriesName, 'Walking Dead - Intégrale');
      expect(p.volumeNumber?.round(), 25);
      expect(
        BookSeriesNormalizer.hitBelongsToSeries(
          'Walking Dead - Intégrale - Tome 25',
          'Walking Dead',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.hitBelongsToSeries(
          'Walking Dead - Tome 10',
          'Walking Dead',
        ),
        isTrue,
      );
    });

    test('rejette parasites / éditions étrangères', () {
      expect(
        BookVfEdition.isRejectedCatalogTitle(
          'Dungeon Crawler Carl and Matt Dinniman (A Summary)',
        ),
        isTrue,
      );
      expect(
        BookVfEdition.isRejectedCatalogTitle(
          'Dungeon Crawler Carl (svensk utgåva)',
        ),
        isTrue,
      );
      expect(
        BookVfEdition.isRejectedCatalogTitle(
          'Harry Potter og Føniksordenen',
        ),
        isTrue,
      );
      expect(
        BookVfEdition.isRejectedCatalogTitle('Harry Potter Bakboek'),
        isTrue,
      );
      expect(
        BookVfEdition.isRejectedCatalogTitle(
          'Harry Potter, les raisons d\'un succès',
        ),
        isTrue,
      );
      expect(
        BookVfEdition.isRejectedCatalogTitle('Harry Potter Boxed Set'),
        isTrue,
      );
      expect(BookVfEdition.isFrOrEnLanguage('it'), isFalse);
      expect(BookVfEdition.isFrOrEnLanguage('sv'), isFalse);
      expect(BookVfEdition.isFrOrEnLanguage('fr'), isTrue);
    });
  });

  group('BookSeriesNormalizer', () {
    test('expectedCount / preferredSubcategory toujours null (plus de dicos)', () {
      expect(
        BookSeriesNormalizer.expectedCount('Thorgal', BookSubcategory.bd),
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
      // Sans éditeur manga/BD → Roman (plus de badge « Autre »).
      expect(
        BookSeriesNormalizer.detectSubcategory(seriesName: 'Kingdom'),
        BookSubcategory.novel,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(seriesName: 'Thorgal'),
        BookSubcategory.novel,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(
          subjects: 'Fiction / Fantasy / LitRPG',
        ),
        BookSubcategory.novel,
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
        BookSubcategory.bd,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Dargaud'),
        BookSubcategory.bd,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Dupuis'),
        BookSubcategory.bd,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Casterman'),
        BookSubcategory.bd,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Soleil'),
        BookSubcategory.bd,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(publisher: 'Bamboo'),
        BookSubcategory.bd,
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
          seriesName: 'XIII',
          publisher: 'Dargaud',
          subjects: 'Fiction / Graphic novels',
        ),
        BookSubcategory.bd,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(
          seriesName: 'Walking Dead',
          publisher: 'Delcourt',
          subjects: 'Comics & Graphic Novels',
          author: 'Robert Kirkman',
        ),
        BookSubcategory.comics,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(
          seriesName: 'Walking Dead',
          comicsContent: true,
          author: 'Robert Kirkman',
        ),
        BookSubcategory.comics,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(
          seriesName: 'XIII',
          author: 'Jean Van Hamme',
          publisher: 'Dargaud',
        ),
        BookSubcategory.bd,
      );
      expect(
        BookSeriesNormalizer.detectSubcategory(
          seriesName: 'XIII',
          author: 'William Vance',
        ),
        BookSubcategory.bd,
      );
      expect(
        BookSeriesNormalizer.formatAuthorList([
          'Osamu Tezuka',
          'Naoki Urasawa',
          'Takashi Nagasaki',
        ]),
        'Osamu Tezuka, Naoki Urasawa & Takashi Nagasaki',
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
      expect(BookSubcategory.fromDbValue('roman'), BookSubcategory.novel);
      expect(BookSubcategory.fromDbValue('comics'), BookSubcategory.comics);
      expect(BookSubcategory.fromDbValue('bd'), BookSubcategory.bd);
      expect(BookSubcategory.fromDbValue('comic'), BookSubcategory.bd);
      expect(BookSubcategory.comics.legacyDbValue, 'comic');
      expect(BookSubcategory.bd.dbValue, 'bd');
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

  group('BookVfEdition', () {
    test('rejette Vol. US et accepte Tome VF', () {
      expect(
        BookVfEdition.isUsVolTitle('Kagurabachi, Vol. 10'),
        isTrue,
      );
      expect(
        BookVfEdition.isFrenchEdition(
          title: 'Kagurabachi, Vol. 10',
          language: 'en',
        ),
        isFalse,
      );
      expect(
        BookVfEdition.isFrenchEdition(
          title: 'Kagurabachi - Tome 10',
          language: 'fr',
        ),
        isTrue,
      );
      expect(
        BookVfEdition.canShowUpcoming(
          title: 'Kagurabachi, Vol. 10',
          language: 'en',
          source: 'itunes',
          publishedDate: '2027-01-01',
        ),
        isFalse,
      );
      expect(
        BookVfEdition.canShowUpcoming(
          title: 'Kagurabachi - Tome 11',
          language: 'fr',
          source: 'google_books',
          publishedDate: '2026-11-06',
        ),
        isTrue,
      );
      expect(
        BookVfEdition.canShowUpcoming(
          title: 'Kagurabachi - Tome 12',
          source: 'mangadex',
          publishedDate: '2027-01-01',
        ),
        isFalse,
      );
    });
  });

  group('AnilistMangaService parasite filter', () {
    test('rejette Bathhouse / Bonus / One-Shot', () {
      expect(
        AnilistMangaService.looksLikeParasiteTitle('Kagurabachi'),
        isFalse,
      );
      expect(
        AnilistMangaService.looksLikeParasiteTitle(
          'Kagurabachi: Bathhouse Quest',
        ),
        isTrue,
      );
      expect(
        AnilistMangaService.looksLikeParasiteTitle(
          'Kagurabachi Bonus Chapter',
        ),
        isTrue,
      );
      expect(
        AnilistMangaService.looksLikeParasiteTitle('One-Shot Special'),
        isTrue,
      );
    });
  });

  group('MangaDexService parasite filter', () {
    test('rejette Bonus / Fan Colored / Colored / Doujinshi / Anthology / Side Story', () {
      expect(MangaDexService.looksLikeParasiteTitle('Kagurabachi'), isFalse);
      expect(
        MangaDexService.looksLikeParasiteTitle('Kagurabachi (Fan Colored)'),
        isTrue,
      );
      expect(
        MangaDexService.looksLikeParasiteTitle('Kagurabachi: Bonus Chapter'),
        isTrue,
      );
      expect(
        MangaDexService.looksLikeParasiteTitle('One Piece Colored'),
        isTrue,
      );
      expect(
        MangaDexService.looksLikeParasiteTitle('Naruto Doujinshi'),
        isTrue,
      );
      expect(
        MangaDexService.looksLikeParasiteTitle('One Piece Anthology'),
        isTrue,
      );
      expect(
        MangaDexService.looksLikeParasiteTitle('Boruto Side Story'),
        isTrue,
      );
    });

    test('isParasiteMangaEntry lit title + altTitles', () {
      expect(
        MangaDexService.isParasiteMangaEntry({
          'attributes': {
            'title': {'en': 'Kagurabachi (Fan Colored)'},
            'altTitles': [],
            'tags': [],
          },
        }),
        isTrue,
      );
      expect(
        MangaDexService.isParasiteMangaEntry({
          'attributes': {
            'title': {'ja-ro': 'Kagurabachi'},
            'altTitles': [
              {'en': 'Kagurabachi: Bonus Chapter'},
            ],
            'tags': [],
          },
        }),
        isTrue,
      );
      expect(
        MangaDexService.isParasiteMangaEntry({
          'attributes': {
            'title': {'en': 'Kagurabachi'},
            'altTitles': [
              {'fr': 'Kagurabachi'},
            ],
            'tags': [],
          },
        }),
        isFalse,
      );
    });
  });

  group('séries distinctes et synopsis', () {
    test('Jujutsu Kaisen, 0 et Modulo ne fusionnent pas', () {
      expect(
        BookSeriesNormalizer.namesMatch('Jujutsu Kaisen', 'Jujutsu Kaisen'),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.namesMatch(
          'Jujutsu Kaisen',
          'Jujutsu Kaisen Modulo',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.namesMatch('Jujutsu Kaisen', 'Jujutsu Kaisen 0'),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.normalizeSeriesKey('Jujutsu Kaisen 0'),
        isNot(BookSeriesNormalizer.normalizeSeriesKey('Jujutsu Kaisen')),
      );
    });

    test('la description ne rattache pas une autre série', () {
      expect(
        BookSeriesNormalizer.catalogIdentityMatchesSeries(
          title: 'The Wandering Inn',
          collectionName: null,
          seriesName: 'Dungeon Crawler Carl',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.catalogIdentityMatchesSeries(
          title: 'La Doublure',
          seriesName: 'Tout le bleu du ciel',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.catalogIdentityMatchesSeries(
          title: 'La Tour des Fous',
          collectionName: 'La Trilogie Hussite',
          seriesName: 'Le Sorceleur',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.catalogIdentityMatchesSeries(
          title: 'La sœur à la perle',
          collectionName: 'Les sept sœurs',
          seriesName: 'Les sept sœurs',
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.normalizeKey('Tout le bleu du ciel'),
        BookSeriesNormalizer.normalizeKey('tout le bleu du ciel'),
      );
    });

    test('cleanSynopsis décode les entités HTML', () {
      final clean = BookVfEdition.cleanSynopsis(
        '<p>Hello&#8203; monde&#xa0;!</p> &quot;Fin&quot; &amp; &#39;ok&#39;',
      );
      expect(clean, isNotNull);
      expect(clean!.contains('&#'), isFalse);
      expect(clean.contains('<p>'), isFalse);
      expect(clean.contains('\u200B'), isFalse);
      expect(clean.contains('"Fin"'), isTrue);
      expect(clean.contains('&'), isTrue);
    });

    test('synopsis en pages qui finissent sur un point', () {
      final pages = BookVfEdition.synopsisPages(
        'Une phrase. Deuxième phrase. Troisième phrase.',
      );
      expect(pages.length, 1);
      expect(pages.first.contains('Troisième'), isTrue);
      final long = BookVfEdition.synopsisPages(
        List.filled(8, 'Phrase assez longue pour remplir la page du synopsis.').join(' '),
      );
      expect(long.length, greaterThan(1));
      for (final page in long) {
        expect(page.trim().endsWith('.'), isTrue);
      }
    });

    test('cleanSynopsis coupe Source et Notes', () {
      final clean = BookVfEdition.cleanSynopsis(
        'Cute girl wizard Lucy wants to join the Fairy Tail club today. '
        '(Source: VIZ Media) Notes: - Ranked 1st in Japan.',
      );
      expect(clean, isNotNull);
      expect(clean!.contains('Lucy'), isTrue);
      expect(clean.contains('Source'), isFalse);
      expect(clean.contains('Ranked'), isFalse);
    });

    test('la requête garde un titre qui contient tous les mots', () {
      expect(
        BookSeriesNormalizer.queryWordsMatchIdentity(
          query: 'dungeon crawler',
          title: 'Dungeon Crawler Carl',
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.queryWordsMatchIdentity(
          query: 'dungeon crawler',
          title: 'The Wandering Inn',
        ),
        isFalse,
      );
      expect(GoogleBooksService.opensCircuit(429, ''), isTrue);
      expect(GoogleBooksService.opensCircuit(503, ''), isTrue);
      expect(
        GoogleBooksService.opensCircuit(
          503,
          '{"reason":"backendFailed"}',
        ),
        isFalse,
      );
      expect(GoogleBooksService.opensCircuit(200, ''), isFalse);
      expect(
        GoogleBooksService.opensCircuit(200, '{"quota_limit_value": "0"}'),
        isTrue,
      );
      expect(
        GoogleBooksService.titleMatchesBooksQuery(
          'Jujutsu Kaisen T04',
          '"Jujutsu Kaisen" "Akutami Gege"',
        ),
        isTrue,
      );
      expect(
        GoogleBooksService.titleMatchesBooksQuery(
          'My Hero Academia T41',
          '"Jujutsu Kaisen" "Akutami Gege"',
        ),
        isFalse,
      );
      expect(
        GoogleBooksService.titleMatchesBooksQuery(
          'Dungeon Crawler Carl',
          'dungeon crawler',
        ),
        isTrue,
      );
    });

    test('Sept Sœurs : accent, sœur numérotée, pas le manga d’étude', () {
      expect(
        BookSeriesNormalizer.textMentionsSeries(
          'Les cinq premiers tomes de sa série Les Sept sœurs',
          'les sept soeurs',
        ),
        isTrue,
      );
      expect(
        BookTitleParser.sisterOrdinal(
          'Ally, la deuxième sœur au tempérament tempétueux',
        ),
        2,
      );
      expect(
        BookTitleParser.isCompanionOrStudyTitle(
          "Les sept soeurs - tome 1 de Lucinda Riley (Analyse de l'œuvre)",
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.titleSharesQueryWord(
          'les sept soeurs',
          'La sœur de la tempête',
        ),
        isTrue,
      );
    });

    test('Thorgal : le spin-off et le Volume anglais ne prennent pas le tome', () {
      expect(
        BookSeriesNormalizer.hitBelongsToSeries(
          'La Jeunesse de Thorgal - Tome 5 - Slive',
          'Thorgal',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.hitBelongsToSeries(
          'Thorgal - Tome 4  La galère noire',
          'Thorgal',
        ),
        isTrue,
      );
      expect(
        BookTitleParser.isFrenchTomeTitle('Thorgal - Tome 20 - La Marque'),
        isTrue,
      );
      expect(
        BookTitleParser.isEnglishVolumeTitle(
          'Thorgal - Volume 20 - Kriss of Valnor',
        ),
        isTrue,
      );
      expect(
        BookTitleParser.isEnglishVolumeTitle(
          'Thorgal - Tome 28 - Kriss de Valnor',
        ),
        isFalse,
      );
    });

    test('Sept Sœurs : description + même auteur relie le tome', () {
      expect(
        BookSeriesNormalizer.descriptionBindsToSeries(
          author: 'Lucinda Riley',
          expectedAuthor: 'Lucinda Riley',
          title: 'La sœur à la perle',
          description:
              'Quatrième tome de la saga Les Sept Sœurs, par Lucinda Riley.',
          seriesName: 'Les sept sœurs',
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.descriptionBindsToSeries(
          author: 'Andrzej Sapkowski',
          expectedAuthor: 'Andrzej Sapkowski',
          title: 'La Trilogie Hussite - Tome 1',
          description: "Premier tome, par l'auteur du Sorceleur.",
          seriesName: 'Le Sorceleur',
        ),
        isFalse,
      );
      expect(
        BookTitleParser.volumeFromLandmark(
          "Harry Potter à l'école des sorciers",
        ),
        1,
      );
      expect(
        BookTitleParser.volumeFromLandmark(
          'Harry Potter and the Deathly Hallows',
        ),
        7,
      );
    });

    test('fiches de lecture rejetées', () {
      expect(
        BookVfEdition.isRejectedCatalogTitle(
          'Harry Potter à l\'école des sorciers',
          publisher: 'lepetitlitteraire.fr',
        ),
        isTrue,
      );
      expect(
        BookVfEdition.isRejectedCatalogTitle(
          'Harry Potter',
          subtitle: "Analyse de l'œuvre",
        ),
        isTrue,
      );
      expect(
        BookVfEdition.isRejectedCatalogTitle(
          'Harry Potter',
          author: 'Guide de lecture',
        ),
        isTrue,
      );
      expect(
        BookVfEdition.isRejectedCatalogTitle(
          "Harry Potter à l'école des sorciers",
          author: 'J.K. Rowling',
        ),
        isFalse,
      );
    });

    test('fromJson tolère les champs nuls', () {
      final series = BookSeries.fromJson({
        'id': null,
        'owner_id': null,
        'name': null,
        'subcategory': null,
        'user_rating': null,
        'expected_volume_count': null,
        'metadata': null,
      });
      expect(series.id, isEmpty);
      expect(series.name, 'Sans titre');
      expect(series.subcategory, BookSubcategory.other);
      expect(series.userRating, isNull);
      expect(series.expectedVolumeCount, isNull);

      final volume = BookVolume.fromJson({
        'id': 'v1',
        'series_id': 's1',
        'volume_number': null,
        'sort_index': null,
        'metadata': null,
      });
      expect(volume.volumeNumber, 0);
      expect(volume.sortIndex, 0);
      expect(volume.coverUrl, isNull);
      expect(volume.publishedDate, isNull);

      final item = CollectionItem.fromJson({
        'id': null,
        'title': null,
        'category': null,
        'rating': null,
        'quantity': null,
        'subcategory': null,
      });
      expect(item.id, isEmpty);
      expect(item.title, isEmpty);
      expect(item.rating, isNull);
      expect(item.quantity, 0);
    });

    test('à paraître seulement après aujourd\'hui + 2 jours', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final later = DateTime.now().add(const Duration(days: 4));
      expect(
        BookIntelligenceService.isFuturePublishedDate(
          tomorrow.toIso8601String(),
        ),
        isFalse,
      );
      expect(
        BookIntelligenceService.isFuturePublishedDate(later.toIso8601String()),
        isTrue,
      );
      expect(BookIntelligenceService.isFuturePublishedDate(null), isFalse);
    });

    test('Sept Sœurs : le numéro vient de la description une fois la collection connue', () {
      final ranked = BookIntelligenceService.enrichAndRank(
        [
          {
            'title': 'La sœur à la perle',
            'author': 'Lucinda Riley',
            'collection_name': 'Les sept sœurs',
            'series_title': 'Les sept sœurs',
            'description': 'Quatrième tome de la saga.',
          },
          {
            'title': 'The Wandering Inn',
            'author': 'Pirateaba',
            'description': 'for fans of Dungeon Crawler Carl',
          },
        ],
        subcategory: BookSubcategory.novel,
        filters: const BookSearchFilters(titleQuery: 'Les sept sœurs'),
      );
      expect(ranked, isNotEmpty);
      expect(ranked.first.parsed.volumeNumber, 4);
      expect(
        BookSeriesNormalizer.namesMatch(
          ranked.first.parsed.seriesName ?? '',
          'Les sept sœurs',
        ),
        isTrue,
      );
      expect(
        ranked.any((h) => (h.raw['title'] ?? '').contains('Wandering')),
        isFalse,
      );
    });
  });

  group('homonymes et sous-titres', () {
    test('un spin-off n est pas la série', () {
      expect(
        BookSeriesNormalizer.isSpinOffSeriesName(
          'One Piece Doors',
          'One Piece',
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.isSpinOffSeriesName(
          'Sur les mers de one piece',
          'One Piece',
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.isSpinOffSeriesName(
          'Dofus Monster',
          'Monster',
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.isSpinOffSeriesName(
          'One Piece - Édition originale',
          'One Piece',
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.isSpinOffSeriesName('Thorgal', 'Thorgal'),
        isFalse,
      );
    });

    test('manga : un autre auteur ne remplace pas la série', () {
      expect(
        BookSeriesNormalizer.rejectAsDifferentWork(
          title: 'Monster Tome 2',
          seriesName: 'Monster',
          author: 'Michael Grant',
          expectedAuthor: 'Naoki Urasawa',
          mangaAuthorRequired: true,
        ),
        isTrue,
      );
      expect(
        BookSeriesNormalizer.rejectAsDifferentWork(
          title: 'Monster Tome 2',
          seriesName: 'Monster',
          author: 'Naoki Urasawa',
          expectedAuthor: 'Naoki Urasawa',
          mangaAuthorRequired: true,
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.rejectAsDifferentWork(
          title: 'Thorgal - Tome 4',
          seriesName: 'Thorgal',
          author: 'Jean Van Hamme',
          expectedAuthor: 'Yann',
          mangaAuthorRequired: false,
        ),
        isFalse,
      );
      expect(
        BookSeriesNormalizer.rejectAsDifferentWork(
          title: 'One Piece Doors - Tome 01',
          seriesName: 'One Piece',
          author: 'Eiichiro Oda',
          expectedAuthor: 'Eiichiro Oda',
          mangaAuthorRequired: true,
        ),
        isTrue,
      );
    });

    test('le sous-titre Série - N donne le tome', () {
      expect(
        BookTitleParser.volumeFromLabeledSeries(
          'La sœur à la perle : Les sept sœurs - 4',
          'Les sept sœurs',
        ),
        4,
      );
      expect(
        BookTitleParser.volumeFromLabeledSeries(
          'Les sept soeurs, tome 8',
          'Les sept sœurs',
        ),
        8,
      );
      final ranked = BookIntelligenceService.enrichAndRank(
        [
          {
            'title': 'La sœur à la perle',
            'subtitle': 'Les sept sœurs - 4',
            'author': 'Lucinda Riley',
            'language': 'fr',
          },
          {
            'title': 'Les sept sœurs - L\'Intégrale',
            'author': 'Lucinda Riley',
            'language': 'fr',
          },
        ],
        subcategory: BookSubcategory.novel,
        filters: const BookSearchFilters(titleQuery: 'Les sept sœurs'),
      );
      final perle = ranked.where(
        (h) => (h.raw['title'] ?? '').contains('perle'),
      );
      expect(perle, hasLength(1));
      expect(perle.single.parsed.volumeNumber, 4);
      expect(
        BookSeriesNormalizer.namesMatch(
          perle.single.parsed.seriesName ?? '',
          'Les sept sœurs',
        ),
        isTrue,
      );
    });

    test('le synopsis se coupe sur un point', () {
      const text =
          'Première phrase assez longue pour compter vraiment le quota. '
          'Deuxième phrase qui termine déjà la première page du synopsis. '
          'Troisième phrase qui doit basculer sur la page suivante clairement. '
          'Quatrième phrase encore pour forcer une coupure nette.';
      final pages = BookVfEdition.synopsisPages(text);
      expect(pages.length, greaterThan(1));
      for (final page in pages) {
        expect(RegExp(r'[.!?…]$').hasMatch(page.trim()), isTrue);
      }
    });
  });
}
