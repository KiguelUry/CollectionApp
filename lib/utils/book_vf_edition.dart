/// Filtres éditions — anti-pollution US VIZ (`Vol. N`) + langues + parasites.
/// Ne rejette PAS MangaDex/AniList (métadonnées EN/romaji normales).
abstract final class BookVfEdition {
  /// Titres US du type « Kagurabachi, Vol. 10 ».
  static final usVolTitleRe = RegExp(
    r'\bVol\.\s*\d+\b',
    caseSensitive: false,
  );

  /// Guides / IA / companions non officiels (Google Books spam).
  /// Motifs génériques — jamais une liste de titres de séries.
  static final parasiteTitleRe = RegExp(
    r'\b(?:summary|study\s*guide|companion(?:\s+guide)?|after\s+reading|'
    r'analysis|unauthorized|reflections\s+on|quiz\s*book|'
    r'fiche\s+de\s+lecture|collection\s+compl[eè]te|'
    r'boxed\s+set|bakboek|'
    r'raisons\s+d.?un\s+succ[eè]s|'
    r'lepetitlitteraire|petit\s+litt[eé]raire|'
    r'analyse\s+de\s+l.?œuvre|analyse\s+de\s+l.?oeuvre|'
    r'profil\s+d.?une\s+œuvre|profil\s+d.?une\s+oeuvre|'
    r'commentaire\s+compos[eé]|'
    r'r[eé]sum[eé]\s+et\s+analyse|guide\s+de\s+lecture)\b',
    caseSensitive: false,
  );

  /// Éditions étrangères repérables dans le titre (même si language manquant).
  static final foreignEditionTitleRe = RegExp(
    r'svensk\s+utg[aå]va|edizione\s+italiana|'
    r'[æøå]|enth[uü]llt|\befsanesi\b|\bbakboek\b',
    caseSensitive: false,
  );

  static bool isUsVolTitle(String title) => usVolTitleRe.hasMatch(title);

  /// Titre, sous-titre, auteur ou éditeur à exclure (parasite ou édition IT/SV…).
  static bool isRejectedCatalogTitle(
    String title, {
    String? subtitle,
    String? author,
    String? publisher,
  }) {
    final blob = '$title ${subtitle ?? ''} ${author ?? ''} ${publisher ?? ''}';
    if (parasiteTitleRe.hasMatch(blob)) return true;
    if (foreignEditionTitleRe.hasMatch(blob)) return true;
    return false;
  }

  /// Retire les balises et décode les entités HTML (numériques et nommées).
  static String? cleanSynopsis(String? raw) {
    if (raw == null) return null;
    var s = raw.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = s.replaceAll('&#8203;', '').replaceAll('\u200B', '');
    s = s
        .replaceAll(RegExp(r'&#x0*a0;', caseSensitive: false), ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&nbsp;', ' ');
    s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final c = int.tryParse(m.group(1)!, radix: 16);
      if (c == null || c == 0x200B) return '';
      if (c == 0xA0) return ' ';
      return String.fromCharCode(c);
    });
    s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final c = int.tryParse(m.group(1)!);
      if (c == null || c == 0x200B) return '';
      if (c == 160) return ' ';
      return String.fromCharCode(c);
    });
    s = s
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    final cut = RegExp(
      r'(?:\(\s*Source\s*:|\[\s*Source\s*:|\[\s*Written by|\bNotes\s*:|'
      r'\bAwards\s*:|---\s*Notes)',
      caseSensitive: false,
    ).firstMatch(s);
    if (cut != null) s = s.substring(0, cut.start);
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length < 20) return null;
    return s;
  }

  /// Pages d'environ 320–400 caractères, ou 3 à 4 phrases.
  static List<String> synopsisPages(String clean) {
    final text = clean.trim();
    if (text.isEmpty) return const [];
    final sentences = text
        .split(RegExp(r'(?<=[.!?…])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.length <= 1) return [text];
    final pages = <String>[];
    final buf = <String>[];
    var chars = 0;
    void flush() {
      if (buf.isEmpty) return;
      pages.add(buf.join(' '));
      buf.clear();
      chars = 0;
    }

    for (final sentence in sentences) {
      final sep = buf.isEmpty ? 0 : 1;
      final next = chars + sep + sentence.length;
      if (buf.isNotEmpty &&
          (buf.length >= 4 || next > 400 || (buf.length >= 3 && chars >= 320))) {
        flush();
      }
      buf.add(sentence);
      chars += (buf.length > 1 ? 1 : 0) + sentence.length;
    }
    flush();
    return pages;
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
