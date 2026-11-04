import 'package:flutter/foundation.dart';

import '../config/app_env.dart';
import '../config/supabase_public_config.dart';

/// CDN images gratuit (Cloudflare) — CORS CanvasKit + WebP léger.
const kWsrvHost = 'wsrv.nl';

/// Sur le web, route les couvertures selon le domaine (direct / wsrv / catalog-proxy).
String coverUrlForWeb(String url, {int width = 360}) =>
    proxyImageUrl(url, width: width);

bool _isDirectCorsHost(String host) {
  return host.contains('anilist.co') ||
      host.contains('image.tmdb.org') ||
      host.contains('openlibrary.org') ||
      host.contains('rawg.io') ||
      host.contains('wikia.') ||
      host.contains('fandom.com') ||
      host.contains('nocookie.net') ||
      host.contains('brickset.com') ||
      host.contains('tcgdex.net') ||
      host.contains('scryfall.com') ||
      host.contains('ygoprodeck.com');
}

/// Domaines qui passent par wsrv (CORS CanvasKit et/ou rate-limit amont).
bool _needsWsrv(String host) {
  return host.contains('geekdo-images.com') ||
      host.contains('discogs.com') ||
      host.contains('mzstatic.com') ||
      host.contains('books.google.') ||
      host.contains('googleapis.com') ||
      host.contains('googleusercontent.com');
}

bool _isMangaDexUploads(String host) =>
    host == 'uploads.mangadex.org' || host.endsWith('.mangadex.org');

/// Force miniature MangaDex (~30 Ko) : `.256.jpg` ou `.512.jpg`.
String mangaDexThumbnailUrl(String url, {int width = 360}) {
  var u = url.trim();
  if (u.isEmpty) return u;
  final size = width <= 280 ? '256' : '512';
  u = u.replaceFirst(
    RegExp(r'\.(256|512)\.jpe?g$', caseSensitive: false),
    '.jpg',
  );
  if (RegExp(r'\.jpe?g$', caseSensitive: false).hasMatch(u)) {
    u = u.replaceFirst(
      RegExp(r'\.jpe?g$', caseSensitive: false),
      '.$size.jpg',
    );
  } else if (!u.contains('.$size.jpg')) {
    u = '$u.$size.jpg';
  }
  return u;
}

/// Apple : source raisonnable (évite 44× `600x600bb` → ERR_CONNECTION_CLOSED).
String _appleSourceForWsrv(String url) {
  return url.replaceAll(RegExp(r'\d+x\d+bb'), '300x300bb');
}

/// Google Books : https + retire `edge=curl` (CORS / cache).
String _googleBooksClean(String url) {
  var u = url.replaceAll(RegExp(r'[&?]edge=curl'), '');
  u = u.replaceAll('?&', '?').replaceAll('&&', '&');
  if (u.endsWith('?') || u.endsWith('&')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

String _catalogProxyImageUrl(String httpsUrl) {
  final base = AppEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
  final anon = AppEnv.supabaseAnonKey.trim().isNotEmpty
      ? AppEnv.supabaseAnonKey.trim()
      : SupabasePublicConfig.anonKey;
  return Uri.parse('$base/functions/v1/catalog-proxy').replace(
    queryParameters: {
      'url': httpsUrl,
      'apikey': anon,
    },
  ).toString();
}

/// Helper central de routage d'images.
///
/// - MangaDex uploads → catalog-proxy (jamais wsrv)
/// - BGG / Discogs / Apple mzstatic / Google Books → wsrv.nl
/// - Autres CDN CORS-friendly → HTTPS direct
String proxyImageUrl(
  String url, {
  int width = 360,
  bool crop = false,
}) {
  var src = url.trim();
  if (src.isEmpty) return src;
  if (src.startsWith('//')) src = 'https:$src';

  final uri = Uri.tryParse(src);
  if (uri == null || uri.host.isEmpty) return src;

  final host = uri.host.toLowerCase();
  if (host == kWsrvHost ||
      host == 'localhost' ||
      host.startsWith('127.')) {
    return src;
  }

  // Stockage privé Supabase : laisser tel quel (auth requise).
  if (uri.path.contains('/storage/v1/object/') &&
      !uri.path.contains('/storage/v1/object/public/')) {
    return src;
  }

  var https = uri.replace(scheme: 'https').toString();

  // MangaDex : JAMAIS wsrv (403 amont → 400 wsrv en boucle).
  if (_isMangaDexUploads(host)) {
    final thumb = mangaDexThumbnailUrl(https, width: width);
    if (kIsWeb) return _catalogProxyImageUrl(thumb);
    return thumb;
  }

  if (_needsWsrv(host)) {
    if (host.contains('mzstatic.com')) {
      https = _appleSourceForWsrv(https);
      // Plafonne la sortie wsrv pour ne pas surcharger Apple en amont.
      return _wsrv(https, width: width.clamp(64, 300), crop: crop);
    }
    if (host.contains('books.google.') ||
        host.contains('googleapis.com') ||
        host.contains('googleusercontent.com')) {
      https = _googleBooksClean(https);
    }
    return _wsrv(https, width: width, crop: crop);
  }

  if (_isDirectCorsHost(host)) {
    return https;
  }

  return https;
}

String _wsrv(
  String httpsUrl, {
  required int width,
  bool crop = false,
}) {
  final w = width.clamp(64, 1600);
  final q = StringBuffer(
    'https://$kWsrvHost/?url=${Uri.encodeComponent(httpsUrl)}'
    '&w=$w',
  );
  if (crop) {
    q.write('&h=$w&fit=cover&we');
  }
  q.write('&output=webp&q=80');
  return q.toString();
}
