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
String coverUrlForDisplay(String url, {required bool large}) =>
    coverUrlForWeb(
      resolveCoverSourceUrl(url, large: large),
      width: large ? 1000 : 600,
    );

const kThumbnailCdnHost = 'wsrv.nl';
const kThumbnailSize = 260;

/// Vignette de grille : routage intelligent via [proxyImageUrl]
/// (direct CORS / wsrv BGG-Discogs / catalog-proxy MangaDex).
String gridThumbnailUrl(
  String url, {
  bool crop = false,
  int size = kThumbnailSize,
}) {
  final src = resolveCoverSourceUrl(url, large: size > 320).trim();
  if (src.isEmpty) return url;
  return proxyImageUrl(src, width: size, crop: crop);
}

/// Photo de matériel BGG. On garde l'URL geekdo telle quelle (`imageurl_lg`) :
/// réécrire `/fit-in/1024x1024/` en 1200 renvoie HTTP 404.
String bggMaterialPhotoUrl(
  String raw, {
  int width = 600,
  int quality = 80,
}) {
  var url = raw.trim().replaceAll(r'\', '');
  if (url.startsWith('//')) url = 'https:$url';
  if (!url.startsWith('http')) return '';
  if (url.contains('wsrv.nl')) {
    final uri = Uri.parse(url);
    final params = Map<String, String>.from(uri.queryParameters);
    params['w'] = '$width';
    params['q'] = '$quality';
    params['output'] = 'webp';
    return uri.replace(queryParameters: params).toString();
  }
  return proxyImageUrl(url, width: width);
}

/// URL source normalisée (taille adaptée), sans proxy web.
String resolveCoverSourceUrl(String url, {required bool large}) {
  var resolved = url.trim();
  if (resolved.startsWith('//')) {
    resolved = 'https:$resolved';
  }

  // Grilles / listes : vignettes BGG plus légères.
  if (!large && resolved.contains('geekdo-images.com') &&
      resolved.contains('/fit-in/')) {
    resolved = resolved.replaceFirst(
      RegExp(r'/fit-in/\d+x\d+/'),
      '/fit-in/320x320/',
    );
  }

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

  return resolved;
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
