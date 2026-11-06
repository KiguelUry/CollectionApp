import 'app_env.dart';
import 'supabase_public_config.dart';

/// Proxy catalogue (MangaDex covers + APIs CORS).
///
/// 1. Crée le Worker Cloudflare `paloma-catalog-proxy` (voir
///    `cloudflare/paloma-catalog-proxy.js`).
/// 2. Colle ton URL workers.dev dans [kCloudflareCatalogProxyUrl] (sans `/` final)
///    **ou** passe `--dart-define=CATALOG_PROXY_URL=https://...workers.dev`
///    **ou** `CATALOG_PROXY_URL=` dans `.env`.
/// 3. Rebuild / redéploie le front.
///
/// Vide → fallback Edge Function Supabase (avec apikey).
/// Renseigné → Cloudflare, **sans** apikey (0 preflight OPTIONS).
const String kCloudflareCatalogProxyUrl =
    'https://paloma-catalog-proxy.kilian-ury.workers.dev';

/// URL de base du proxy actif (Cloudflare si configuré, sinon Supabase).
String catalogProxyBaseUrl() {
  final hardcoded = kCloudflareCatalogProxyUrl.trim();
  if (hardcoded.isNotEmpty) {
    return hardcoded.replaceAll(RegExp(r'/+$'), '');
  }
  final fromEnv = AppEnv.catalogProxyUrl?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return fromEnv.replaceAll(RegExp(r'/+$'), '');
  }
  final supabase = AppEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$supabase/functions/v1/catalog-proxy';
}

bool get usesCloudflareCatalogProxy {
  final base = catalogProxyBaseUrl();
  return !base.contains('supabase.co');
}

/// Construit l'URI proxy pour une URL cible.
/// Cloudflare : `?url=` seul. Supabase : `?url=` + `apikey=`.
Uri buildCatalogProxyUri(String targetHttpsUrl) {
  final base = catalogProxyBaseUrl();
  final params = <String, String>{'url': targetHttpsUrl};
  if (!usesCloudflareCatalogProxy) {
    final anon = AppEnv.supabaseAnonKey.trim().isNotEmpty
        ? AppEnv.supabaseAnonKey.trim()
        : SupabasePublicConfig.anonKey;
    params['apikey'] = anon;
  }
  return Uri.parse(base).replace(queryParameters: params);
}
