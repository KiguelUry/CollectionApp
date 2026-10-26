/// Filtres éditions françaises (VF) — rejette pollution US VIZ (`Vol. N`).
abstract final class BookVfEdition {
  /// Titres US du type « Kagurabachi, Vol. 10 ».
  static final usVolTitleRe = RegExp(
    r'\bVol\.\s*\d+\b',
    caseSensitive: false,
  );

  static bool isUsVolTitle(String title) => usVolTitleRe.hasMatch(title);

  /// Langue française (code ISO style `fr`, `fr-FR`).
  static bool isFrenchLanguage(String? language) {
    if (language == null || language.trim().isEmpty) return false;
    final l = language.toLowerCase().trim();
    return l == 'fr' || l.startsWith('fr-') || l.startsWith('fre');
  }

  /// Hit catalogue acceptable pour une collection VF.
  /// Rejette `Vol. N` ; exige `fr` si une langue est déclarée.
  static bool isFrenchEdition({
    required String title,
    String? language,
    String? source,
  }) {
    if (isUsVolTitle(title)) return false;
    if (language != null &&
        language.trim().isNotEmpty &&
        !isFrenchLanguage(language)) {
      return false;
    }
    // iTunes US souvent sans language mais titre « Vol. » — déjà filtré.
    // Source mangadex seule (couverture JP) : OK pour fill cover, pas pour dates.
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
    if (src.contains('mangadex') && !src.contains('google') && !src.contains('itunes')) {
      // MangaDex seul = édition JP → pas de badge À paraître VF.
      return false;
    }
    if (language != null &&
        language.trim().isNotEmpty &&
        !isFrenchLanguage(language)) {
      return false;
    }
    // Préfère titres « Tome N » ou source google/itunes FR.
    final hasTome = RegExp(r'\btome\s*\d+', caseSensitive: false).hasMatch(title);
    final frSource = src.contains('google') || src == 'itunes' || src.contains('itunes');
    if (!hasTome && !frSource && !isFrenchLanguage(language)) return false;
    return true;
  }
}
