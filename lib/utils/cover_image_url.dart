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
    coverUrlForWeb(resolveCoverSourceUrl(url, large: large));

const kThumbnailCdnHost = 'wsrv.nl';
const kThumbnailSize = 260;

/// Vignette de grille : 260 px WebP via wsrv.nl (`w=260&q=80&output=webp`).
/// La taille est plafonnée pour limiter les textures WebGL de Firefox.
/// Le décodage se fait en octets (HttpGet), pas via une balise HTML.
/// Renvoie [url] inchangée si elle n'est pas transformable.
String gridThumbnailUrl(
  String url, {
  bool crop = false,
  int size = kThumbnailSize,
}) {
  final src = resolveCoverSourceUrl(url, large: size > 320);
  final uri = Uri.tryParse(src);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return url;
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty ||
      host == kThumbnailCdnHost ||
      host == 'localhost' ||
      host.startsWith('127.')) {
    return url;
  }
  // Stockage Supabase : seules les URLs publiques sont stables.
  if (uri.path.contains('/storage/v1/object/') &&
      !uri.path.contains('/storage/v1/object/public/')) {
    return url;
  }
  return 'https://$kThumbnailCdnHost/?url=${Uri.encodeComponent(src)}'
      '&w=$size&h=$size'
      '&fit=${crop ? 'cover' : 'inside'}&we&output=webp&q=80';
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
  return 'https://wsrv.nl/?url=${Uri.encodeComponent(url)}'
      '&w=$width&q=$quality&output=webp';
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
