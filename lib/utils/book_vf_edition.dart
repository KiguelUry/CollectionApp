/// Filtres éditions — anti-pollution US VIZ (`Vol. N`) uniquement.
/// Ne rejette PAS MangaDex/AniList (métadonnées EN/romaji normales).
abstract final class BookVfEdition {
  /// Titres US du type « Kagurabachi, Vol. 10 ».
  static final usVolTitleRe = RegExp(
    r'\bVol\.\s*\d+\b',
    caseSensitive: false,
  );

  static bool isUsVolTitle(String title) => usVolTitleRe.hasMatch(title);

  /// Langue française (code ISO style `fr`, `fr-FR`, `fre`).
  static bool isFrenchLanguage(String? language) {
    if (language == null || language.trim().isEmpty) return false;
    final l = language.toLowerCase().trim();
    return l == 'fr' ||
        l.startsWith('fr-') ||
        l.startsWith('fre') ||
        l == 'french';
  }

  /// Anglais explicite (pas `null` / `und`).
  static bool isExplicitEnglish(String? language) {
    if (language == null || language.trim().isEmpty) return false;
    final l = language.toLowerCase().trim();
    if (l == 'und' || l == 'zxx') return false;
    return l == 'en' || l.startsWith('en-') || l == 'eng' || l == 'english';
  }

  static bool isCatalogSource(String? source) {
    final s = (source ?? '').toLowerCase();
    return s.contains('google') || s.contains('itunes') || s == 'open_library';
  }

  static bool isOfficialMangaSource(String? source) {
    final s = (source ?? '').toLowerCase();
    return s.contains('mangadex') || s.contains('anilist');
  }

  /// Hit acceptable dans la grille.
  /// Rejette UNIQUEMENT `\bVol\.\s*\d+` (VIZ). Langue null/und = OK.
  /// MangaDex / AniList : jamais rejetés pour la langue.
  static bool isFrenchEdition({
    required String title,
    String? language,
    String? source,
  }) {
    if (isUsVolTitle(title)) return false;
    if (isOfficialMangaSource(source)) return true;
    // null / und / vide → garder (romans, BD sans code langue).
    if (language == null || language.trim().isEmpty) return true;
    final l = language.toLowerCase().trim();
    if (l == 'und' || l == 'zxx') return true;
    return true;
  }

  /// Après enrichissement : si des hits FR existent, retire les EN purs GB/iTunes.
  static bool keepInSearchResults({
    required String title,
    String? language,
    String? source,
    required bool frenchResultsPresent,
  }) {
    if (isUsVolTitle(title)) return false;
    if (isOfficialMangaSource(source)) return true;
    if (!frenchResultsPresent) return true;
    if (isCatalogSource(source) && isExplicitEnglish(language)) {
      return false;
    }
    return true;
  }

  /// Date « À paraître » uniquement depuis une fiche VF (jamais US / MD seul).
  static bool canShowUpcoming({
    required String title,
    String? language,
    String? source,
    String? publishedDate,
  }) {
    if (publishedDate == null || publishedDate.isEmpty) return false;
    if (isUsVolTitle(title)) return false;
    final src = (source ?? '').toLowerCase();
    if (src.contains('mangadex') &&
        !src.contains('google') &&
        !src.contains('itunes')) {
      return false;
    }
    if (language != null &&
        language.trim().isNotEmpty &&
        isExplicitEnglish(language)) {
      return false;
    }
    final hasTome =
        RegExp(r'\btome\s*\d+', caseSensitive: false).hasMatch(title);
    final frSource =
        src.contains('google') || src == 'itunes' || src.contains('itunes');
    if (!hasTome && !frSource && !isFrenchLanguage(language)) return false;
    return true;
  }
}
