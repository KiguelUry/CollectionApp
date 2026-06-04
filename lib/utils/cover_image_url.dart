/// Tailles de couvertures Open Library (évite le flou / crop agressif).
enum CoverSize { small, medium, large }

String openLibraryCoverUrl(String coverId, {CoverSize size = CoverSize.medium}) {
  final suffix = switch (size) {
    CoverSize.small => 'S',
    CoverSize.medium => 'M',
    CoverSize.large => 'L',
  };
  return 'https://covers.openlibrary.org/b/id/$coverId-$suffix.jpg';
}

String openLibraryAuthorPhotoUrl(String authorOlid, {CoverSize size = CoverSize.medium}) {
  final suffix = switch (size) {
    CoverSize.small => 'S',
    CoverSize.medium => 'M',
    CoverSize.large => 'L',
  };
  return 'https://covers.openlibrary.org/a/olid/$authorOlid-$suffix.jpg';
}

/// Choisit une URL plus nette pour l'affichage (listes vs fiche détail).
String coverUrlForDisplay(String url, {required bool large}) {
  // Grilles / listes : garder low.webp (chargement plus rapide).
  if (url.contains('assets.tcgdex.net') && large && url.endsWith('/low.webp')) {
    return url.replaceFirst('/low.webp', '/high.webp');
  }
  if (!url.contains('covers.openlibrary.org')) return url;
  if (large) {
    return url.replaceAll(
      RegExp(r'-[SML]\.jpg', caseSensitive: false),
      '-L.jpg',
    );
  }
  return url.replaceAll(RegExp(r'-S\.jpg', caseSensitive: false), '-M.jpg');
}
