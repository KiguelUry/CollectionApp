import 'package:flutter/foundation.dart';

import '../config/app_env.dart';
import '../config/supabase_public_config.dart';

String _catalogAnonKey() {
  final anon = AppEnv.supabaseAnonKey.trim();
  if (anon.isNotEmpty) return anon;
  return SupabasePublicConfig.anonKey;
}

/// Sur le web, route les API CORS-bloquées (MangaDex, iTunes) via l'Edge Function
/// Supabase `catalog-proxy` — plus fiable que allorigins / codetabs (520/522).
Uri proxiedCatalogUri(Uri target) {
  if (!kIsWeb) return target;
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
