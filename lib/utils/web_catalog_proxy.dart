import 'package:flutter/foundation.dart';

import '../config/app_env.dart';
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

/// Sur le web, route les API CORS-bloquées (MangaDex, iTunes) via l'Edge Function
/// Supabase `catalog-proxy` — **JSON uniquement, jamais d'images**.
Uri proxiedCatalogUri(Uri target) {
  if (!kIsWeb) return target;
  // Filet client : aucune image via catalog-proxy (Egress).
  if (_looksLikeImageUri(target)) return target;

  final host = target.host.toLowerCase();
  // openlibrary.org : CORS natif → appel direct (pas de proxy / 502).
  const allowed = {
    'api.mangadex.org',
    'itunes.apple.com',
    'www.googleapis.com',
  };
  if (!allowed.contains(host)) return target;

  final base = AppEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
  final anon = _catalogAnonKey();
  return Uri.parse('$base/functions/v1/catalog-proxy').replace(
    queryParameters: {
      'url': target.toString(),
      'apikey': anon,
    },
  );
}

Map<String, String> proxiedCatalogHeaders([Map<String, String>? extra]) {
  final headers = <String, String>{
    'Accept': 'application/json',
    ...?extra,
  };
  if (kIsWeb) {
    final anon = _catalogAnonKey();
    headers['apikey'] = anon;
    headers['Authorization'] = 'Bearer $anon';
  }
  return headers;
}
