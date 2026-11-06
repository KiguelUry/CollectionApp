import 'package:flutter/foundation.dart';

import '../config/app_env.dart';
import '../config/catalog_proxy_config.dart';
import '../config/supabase_public_config.dart';

String _catalogAnonKey() {
  final anon = AppEnv.supabaseAnonKey.trim();
  if (anon.isNotEmpty) return anon;
  return SupabasePublicConfig.anonKey;
}

final _imagePathRe = RegExp(
  r'\.(jpe?g|png|webp|gif|avif|bmp|svg)(\?|$)',
  caseSensitive: false,
);

bool _looksLikeImageUri(Uri target) {
  final host = target.host.toLowerCase();
  if (host == 'uploads.mangadex.org' ||
      host == 'covers.openlibrary.org' ||
      host.contains('mzstatic.com') ||
      host.contains('geekdo-images.com') ||
      host.contains('googleusercontent.com') ||
      (host.contains('books.google.') &&
          target.path.toLowerCase().contains('/content'))) {
    return true;
  }
  return _imagePathRe.hasMatch(target.path);
}

/// Sur le web, route les API CORS-bloquées (MangaDex, iTunes) via le proxy
/// catalogue (Cloudflare Worker si configuré, sinon Edge Function Supabase).
/// Images : uniquement `uploads.mangadex.org` (voir [proxyImageUrl]).
Uri proxiedCatalogUri(Uri target) {
  if (!kIsWeb) return target;

  final host = target.host.toLowerCase();
  if (host != 'uploads.mangadex.org' && _looksLikeImageUri(target)) {
    return target;
  }

  const allowed = {
    'api.mangadex.org',
    'itunes.apple.com',
    'www.googleapis.com',
    'uploads.mangadex.org',
  };
  if (!allowed.contains(host)) return target;

  return buildCatalogProxyUri(target.toString());
}

/// Headers HTTP pour les appels JSON via proxy.
/// Cloudflare : aucun header custom (évite OPTIONS preflight).
/// Supabase : apikey + Authorization.
Map<String, String> proxiedCatalogHeaders([Map<String, String>? extra]) {
  final headers = <String, String>{
    'Accept': 'application/json',
    ...?extra,
  };
  if (!usesCloudflareCatalogProxy) {
    final anon = _catalogAnonKey();
    headers['apikey'] = anon;
    headers['Authorization'] = 'Bearer $anon';
  }
  return headers;
}
