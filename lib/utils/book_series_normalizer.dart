import '../models/book_subcategory.dart';
import 'book_title_parser.dart';

/// Normalise titres livres → (série, tome) + compteurs connus.
abstract final class BookSeriesNormalizer {
  /// Grandes séries FR / manga (ajustable ensuite via `expected_volume_count`).
  static const knownExpectedVolumes = <String, int>{
    'thorgal': 42,
    'asterix': 40,
    'astérix': 40,
    'tintin': 24,
    'naruto': 72,
    'one piece': 110,
    'dragon ball': 42,
    'gannibal': 13,
    'dungeon crawler carl': 7,
    'kagurabachi': 11,
    'boruto': 20,
    'boruto - two blue vortex': 5,
    'boruto: two blue vortex': 5,
    'blake et mortimer': 30,
    'lucky luke': 80,
    'spirou': 55,
    'boule et bill': 40,
    'XIII': 28,
    'xiii': 28,
    'lanfeust de troy': 8,
    'largo winch': 22,
    'gaston': 19,
    'berserk': 42,
    'attack on titan': 34,
    'l\'attaque des titans': 34,
    'death note': 12,
    'demon slayer': 23,
    'jujutsu kaisen': 26,
    'hunter x hunter': 38,
    'bleach': 74,
    'fullmetal alchemist': 27,
    'vinland saga': 28,
    'vagabond': 37,
    'kingdom': 73,
  };

  /// Séries franco-belges → toujours BD (jamais Roman / Manga).
  static const knownBdSeries = <String>{
    'thorgal',
    'asterix',
    'astérix',
    'tintin',
    'blake et mortimer',
    'lucky luke',
    'spirou',
    'boule et bill',
    'xiii',
    'lanfeust de troy',
    'largo winch',
    'gaston',
  };

  /// Éditeurs manga FR / US.
  static const mangaPublishers = <String>{
    'meian',
    'kana',
    'ki-oon',
    'ki oon',
    'kurokawa',
    'pika',
    'panini manga',
    'panini',
    'crunchyroll',
    'kazé',
    'kaze',
    'glénat manga',
    'glenat manga',
    'delcourt/tonkam',
    'tonkam',
    'soleil manga',
    'akata',
    'vega',
    'viz',
    'viz media',
    'shonen jump',
    'kodansha',
    'shueisha',
  };

  /// Éditeurs BD franco-belge.
  static const bdPublishers = <String>{
    'le lombard',
    'lombard',
    'dargaud',
    'dupuis',
    'casterman',
    'delcourt',
    'soleil',
    'fluide glacial',
    'glénat',
    'glenat',
    'bamboo',
    'rue de sèvres',
    'rue de sevres',
    'futuropolis',
    'dupuis / marsu',
  };

  /// Éditeurs comics US.
  static const comicsPublishers = <String>{
    'urban comics',
    'marvel',
    'dc',
    'dc comics',
    'image comics',
    'dark horse',
    'idw',
    'boom! studios',
    'panini comics',
  };

  /// Déduit Manga / BD / Comics depuis éditeur + titre (jamais la pilule UI).
  static BookSubcategory? detectSubcategory({
    String? seriesName,
    String? title,
    String? publisher,
    String? subjects,
  }) {
    final preferred = seriesName != null && seriesName.isNotEmpty
        ? preferredSubcategory(seriesName)
        : null;
    if (preferred != null) return preferred;
    if (title != null && title.isNotEmpty) {
      final fromTitle = preferredSubcategory(title);
      if (fromTitle != null) return fromTitle;
    }

    final pub = (publisher ?? '').toLowerCase().trim();
    if (pub.isNotEmpty) {
      if (mangaPublishers.any((p) => pub.contains(p))) {
        return BookSubcategory.manga;
      }
      if (comicsPublishers.any((p) => pub.contains(p))) {
        return BookSubcategory.comics;
      }
      // « Glénat » seul = souvent BD ; « Glénat Manga » déjà couvert plus haut.
      if (bdPublishers.any((p) => pub.contains(p))) {
        return BookSubcategory.comic;
      }
    }

    final subj = (subjects ?? '').toLowerCase();
    if (subj.contains('manga') || subj.contains('anime')) {
      return BookSubcategory.manga;
    }
    if (subj.contains('comic') || subj.contains('superhero')) {
      return BookSubcategory.comics;
    }
    if (subj.contains('bande dessinée') ||
        subj.contains('bande dessinee') ||
        subj.contains('graphic novel') ||
        subj.contains('comics & graphic novels - european')) {
      return BookSubcategory.comic;
    }
    return null;
  }

  /// Catégorie préférée pour une série connue (fusion multi-dossiers).
  static BookSubcategory? preferredSubcategory(String seriesName) {
    final key = normalizeKey(seriesName);
    // Toute série « Thorgal » (Mondes de Thorgal, etc.) → BD.
    if (key.contains('thorgal')) return BookSubcategory.comic;
    if (knownBdSeries.contains(key) ||
        knownBdSeries.any((k) => key.startsWith(k) || k.startsWith(key))) {
      return BookSubcategory.comic;
    }
    const manga = {
      'naruto',
      'one piece',
      'dragon ball',
      'gannibal',
      'kagurabachi',
      'kingdom',
      'boruto',
      'berserk',
      'bleach',
      'demon slayer',
      'jujutsu kaisen',
      'death note',
      'vinland saga',
      'vagabond',
      'fullmetal alchemist',
      'hunter x hunter',
      'attack on titan',
      'l\'attaque des titans',
    };
    if (manga.any((k) => key == k || key.startsWith(k) || k.startsWith(key))) {
      return BookSubcategory.manga;
    }
    return null;
  }

  /// Clé de fusion (ignore « - Tome N »).
  static String mergeKey(String rawName) {
    final display = displaySeriesName(rawName);
    return normalizeKey(display);
  }

  static ParsedBookTitle parse(String title) => BookTitleParser.parse(title);

  static String normalizeKey(String name) {
    var s = name.toLowerCase().trim();
    s = s
        .replaceAll(RegExp(r'[–—−]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^the\s+'), '')
        .replaceAll(RegExp(r'^les?\s+'), '');
    return s;
  }

  static bool namesMatch(String a, String b) =>
      BookTitleParser.seriesNamesMatch(normalizeKey(a), normalizeKey(b)) ||
      BookTitleParser.seriesNamesMatch(a, b);

  /// Nombre de tomes attendus (dictionnaire, sinon null).
  static int? expectedCount(String seriesName, [BookSubcategory? subcategory]) {
    final key = normalizeKey(seriesName);
    final direct = knownExpectedVolumes[key];
    if (direct != null) return direct;
    for (final e in knownExpectedVolumes.entries) {
      if (key.startsWith(e.key) || e.key.startsWith(key)) return e.value;
    }
    return null;
  }

  /// Titre d’affichage canonique (sans « - Tome N » / suffixes orphelins).
  static String displaySeriesName(String rawTitle) {
    final parsed = parse(rawTitle);
    var name = parsed.hasSeries
        ? parsed.seriesName!.trim()
        : rawTitle.trim();
    return stripOrphanVolumeSuffix(name);
  }

  /// Retire « - Tome », « - Vol », « Tome », « Volume » sans numéro en fin.
  static String stripOrphanVolumeSuffix(String name) {
    var s = name.trim();
    s = s.replaceAll(RegExp(r'[–—−]'), '-');
    s = s.replaceAll(
      RegExp(
        r'[\s\-–—]*\b(?:tome|tomes|vol\.?|volume|volumes)\s*$',
        caseSensitive: false,
      ),
      '',
    );
    s = s.replaceAll(RegExp(r'[\s,;:\-]+$'), '').trim();
    return s.isEmpty ? name.trim() : s;
  }

  /// Pour les requêtes de couverture : retire « Édition originale », etc.
  static String coverSearchSeriesName(String raw) {
    var s = displaySeriesName(raw);
    s = s.replaceAll(RegExp(r'[–—−]'), '-');
    // Coupe après « - Édition … » / « Édition originale » / omnibus…
    final dashParts = s.split(RegExp(r'\s+-\s+'));
    if (dashParts.length > 1) {
      final kept = <String>[];
      for (final part in dashParts) {
        final low = part.toLowerCase();
        if (low.contains('édition') ||
            low.contains('edition') ||
            low.contains('omnibus') ||
            low.contains('coffret') ||
            low.contains('box set')) {
          break;
        }
        kept.add(part);
      }
      if (kept.isNotEmpty) s = kept.join(' - ');
    }
    s = s.replaceAll(
      RegExp(
        r'\s+(édition|edition)\s+\S+.*$',
        caseSensitive: false,
      ),
      '',
    );
    return s.replaceAll(RegExp(r'[\s,;:\-]+$'), '').trim();
  }
}
