import 'package:flutter/foundation.dart';

import '../config/app_env.dart';
import '../config/supabase_public_config.dart';

/// CDN images gratuit (Cloudflare) — CORS CanvasKit + WebP léger.
/// **Uniquement** pour BGG / Discogs (bloquent le CORS navigateur).
const kWsrvHost = 'wsrv.nl';

/// Sur le web, route les couvertures selon le domaine (direct / wsrv / catalog-proxy).
String coverUrlForWeb(String url, {int width = 360}) =>
    proxyImageUrl(url, width: width);

bool _isDirectCorsHost(String host) {
  return host.contains('mzstatic.com') ||
      host.contains('books.google.') ||
      host.contains('googleapis.com') ||
      host.contains('googleusercontent.com') ||
      host.contains('anilist.co') ||
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

bool _needsWsrv(String host) {
  return host.contains('geekdo-images.com') || host.contains('discogs.com');
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

String _appleBooksLarger(String url) {
  return url
      .replaceAll('100x100bb', '400x400bb')
      .replaceAll('60x60bb', '400x400bb')
      .replaceAll('130x130bb', '400x400bb');
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
/// 1. CDN CORS-friendly → HTTPS direct (jamais wsrv / catalog-proxy)
/// 2. BGG / Discogs → wsrv.nl uniquement
/// 3. MangaDex uploads → catalog-proxy (web) + miniature `.256`/`.512` — **jamais** wsrv
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

  final https = uri.replace(scheme: 'https').toString();

  // MangaDex : JAMAIS wsrv (403 amont → 400 wsrv en boucle).
  if (_isMangaDexUploads(host)) {
    final thumb = mangaDexThumbnailUrl(https, width: width);
    if (kIsWeb) return _catalogProxyImageUrl(thumb);
    return thumb;
  }

  // CORS navigateur OK → direct.
  if (_isDirectCorsHost(host)) {
    if (host.contains('mzstatic.com')) return _appleBooksLarger(https);
    return https;
  }

  // BGG / Discogs : wsrv (CORS bloqué côté navigateur).
  if (_needsWsrv(host)) {
    return _wsrv(https, width: width, crop: crop);
  }

  // Défaut : HTTPS direct (pas de proxy aveugle).
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
  q.write('&output=webp&q=82');
  return q.toString();
}
