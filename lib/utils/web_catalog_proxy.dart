import 'package:flutter/foundation.dart';

import '../config/app_env.dart';

/// Sur le web, route les API CORS-bloquées (MangaDex, iTunes) via l'Edge Function
/// Supabase `catalog-proxy` — plus fiable que allorigins / codetabs (520/522).
Uri proxiedCatalogUri(Uri target) {
  if (!kIsWeb) return target;
  final host = target.host.toLowerCase();
  const allowed = {'api.mangadex.org', 'itunes.apple.com'};
  if (!allowed.contains(host)) return target;

  final base = AppEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
  final anon = AppEnv.supabaseAnonKey;
  return Uri.parse('$base/functions/v1/catalog-proxy').replace(
    queryParameters: {
      'url': target.toString(),
      if (anon.isNotEmpty) 'apikey': anon,
    },
  );
}

Map<String, String> proxiedCatalogHeaders([Map<String, String>? extra]) {
  final headers = <String, String>{
    'Accept': 'application/json',
    ...?extra,
  };
  if (kIsWeb) {
    final anon = AppEnv.supabaseAnonKey;
    if (anon.isNotEmpty) {
      headers['apikey'] = anon;
      headers['Authorization'] = 'Bearer $anon';
    }
  }
  return headers;
}
