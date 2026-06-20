import 'web_image_proxy.dart';

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
  var resolved = url;

  if (large && resolved.contains('geekdo-images.com')) {
    resolved = bggLargeImageUrl(resolved);
    if (resolved.contains('/fit-in/')) {
      resolved = resolved.replaceFirst(
        RegExp(r'/fit-in/\d+x\d+/'),
        '/fit-in/1200x1200/',
      );
    }
  }

  // Grilles / listes : garder low.webp (chargement plus rapide).
  if (resolved.contains('assets.tcgdex.net') &&
      large &&
      resolved.endsWith('/low.webp')) {
    resolved = resolved.replaceFirst('/low.webp', '/high.webp');
  } else if (resolved.contains('covers.openlibrary.org')) {
    if (large) {
      resolved = resolved.replaceAll(
        RegExp(r'-[SML]\.jpg', caseSensitive: false),
        '-L.jpg',
      );
    } else {
      resolved = resolved.replaceAll(
        RegExp(r'-S\.jpg', caseSensitive: false),
        '-M.jpg',
      );
    }
  }

  return coverUrlForWeb(resolved);
}

/// Passe d'une vignette BGG à une image plus nette (sans casser l'URL).
String bggLargeImageUrl(String url) {
  var u = url;
  if (RegExp(r'_t\.(jpg|jpeg|png|webp)', caseSensitive: false).hasMatch(u)) {
    u = u.replaceAll(
      RegExp(r'_t(\.(jpg|jpeg|png|webp))', caseSensitive: false),
      r'$1',
    );
  }
  return u;
}
