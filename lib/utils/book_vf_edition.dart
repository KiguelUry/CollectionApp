/// Filtres éditions — anti-pollution US VIZ (`Vol. N`) + langues + parasites.
/// Ne rejette PAS MangaDex/AniList (métadonnées EN/romaji normales).
abstract final class BookVfEdition {
  /// Titres US du type « Kagurabachi, Vol. 10 ».
  static final usVolTitleRe = RegExp(
    r'\bVol\.\s*\d+\b',
    caseSensitive: false,
  );

  /// Guides / IA / companions non officiels (Google Books spam).
  static final parasiteTitleRe = RegExp(
    r'\b(?:summary|study\s*guide|companion(?:\s+guide)?|after\s+reading|'
    r'analysis|unauthorized|reflections\s+on|quiz\s*book|'
    r'fiche\s+de\s+lecture|collection\s+compl[eè]te|'
    r'boxed\s+set|bakboek|'
    r'les\s+raisons\s+d.?un\s+succ[eè]s|'
    r'le\s+droit\s+dans\s+la\s+saga|'
    r'la\s+magie\s+r[eé]v[eé]l|'
    r"l.?enfant\s+h[eé]ros|"
    r'monde\s+antique\s+de|'
    r'galileo\s*&\s*harry)\b',
    caseSensitive: false,
  );

  /// Éditions étrangères repérables dans le titre (même si language manquant).
  static final foreignEditionTitleRe = RegExp(
    r'svensk\s+utg[aå]va|il\s+giorno\s+del\s+giudizio|il\s+varco\s+degli|'
    r'il\s+ricettario|edizione\s+italiana|'
    r'\bog\s+føniks|\bog\s+foniks|harry\s+potter\s+og\b|'
    r'\benth[uü]llt\b|\befsanesi\b|'
    r'harry\s+potter\s+og\s+f|'
    r'\bbakboek\b',
    caseSensitive: false,
  );

  static bool isUsVolTitle(String title) => usVolTitleRe.hasMatch(title);

  /// Titre / sous-titre à exclure du catalogue (parasite ou édition IT/SV…).
  static bool isRejectedCatalogTitle(String title, {String? subtitle}) {
    final blob = '$title ${subtitle ?? ''}';
    if (parasiteTitleRe.hasMatch(blob)) return true;
    if (foreignEditionTitleRe.hasMatch(blob)) return true;
    return false;
  }

  /// FR ou EN uniquement (codes ISO).
  static bool isFrOrEnLanguage(String? language) {
    if (language == null || language.trim().isEmpty) return true;
    final l = language.toLowerCase().trim();
    if (l == 'und' || l == 'zxx') return true;
    return isFrenchLanguage(language) || isExplicitEnglish(language);
  }

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
  /// Rejette VIZ `Vol. N`, parasites, titres IT/SV, langues hors fr/en.
  /// MangaDex / AniList : jamais rejetés pour la langue.
  static bool isFrenchEdition({
    required String title,
    String? language,
    String? source,
  }) {
    if (isUsVolTitle(title)) return false;
    if (isRejectedCatalogTitle(title)) return false;
    if (isOfficialMangaSource(source)) return true;
    if (!isFrOrEnLanguage(language)) return false;
    return true;
  }

  /// Après enrichissement : FR d'abord ; EN seulement si pas de FR pour combler.
  /// Rejette toujours it/es/sv/… et les parasites.
  static bool keepInSearchResults({
    required String title,
    String? language,
    String? source,
    required bool frenchResultsPresent,
  }) {
    if (isUsVolTitle(title)) return false;
    if (isRejectedCatalogTitle(title)) return false;
    if (isOfficialMangaSource(source)) return true;
    if (isCatalogSource(source) && !isFrOrEnLanguage(language)) return false;
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
