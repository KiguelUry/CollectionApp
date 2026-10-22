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
    'kagurabachi': 8,
    'blake et mortimer': 30,
    'lucky luke': 80,
    'spirou': 55,
    'boule et bill': 40,
    'XIII': 28,
    'xiii': 28,
    'lanfeust de troy': 8,
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
  };

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

  /// Titre d’affichage canonique (sans « - Tome N »).
  static String displaySeriesName(String rawTitle) {
    final parsed = parse(rawTitle);
    if (parsed.hasSeries) return parsed.seriesName!.trim();
    return rawTitle.trim();
  }
}
