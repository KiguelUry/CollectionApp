import 'package:flutter/foundation.dart';

/// CDN images gratuit (Cloudflare) — CORS CanvasKit + WebP léger.
/// **0 octet d'Egress Supabase** (remplace `functions/v1/image-proxy`).
const kWsrvHost = 'wsrv.nl';

/// Sur le web, route les couvertures externes via [wsrv.nl]
/// (`w` / WebP) — jamais via `catalog-proxy` ni `image-proxy`.
String coverUrlForWeb(String url, {int width = 360}) =>
    proxyImageUrl(url, width: width);

/// Helper central : images externes → wsrv.nl (web), sinon URL https.
///
/// - Force `http://` → `https://`
/// - N'encode jamais une URL déjà sur wsrv.nl
/// - **Aucune** image ne passe par `functions/v1/catalog-proxy`
String proxyImageUrl(String url, {int width = 360}) {
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

  // Hors web : MangaDex / Google Books / Apple peuvent charger en direct
  // (sauf hotlink MD parfois) — wsrv reste utile pour compresser partout.
  if (!kIsWeb) {
    // Mobile : wsrv pour MangaDex (anti-hotlink Referer) + gros JPG.
    if (host.contains('mangadex.org') ||
        host.contains('books.google.') ||
        host.contains('googleusercontent.com') ||
        host.contains('mzstatic.com')) {
      return _wsrv(https, width: width);
    }
    return https;
  }

  return _wsrv(https, width: width);
}

String _wsrv(String httpsUrl, {required int width}) {
  final w = width.clamp(64, 1600);
  return 'https://$kWsrvHost/?url=${Uri.encodeComponent(httpsUrl)}'
      '&w=$w&output=webp&q=82';
}
