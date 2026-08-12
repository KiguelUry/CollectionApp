import 'rawg_service.dart';

/// Jeux vidéo — recherche via proxy Supabase (RAWG + Steam, cache).
class VideogameCatalogService {
  static bool get proxyEnabled => RawgService.useProxy;

  static String get catalogLabel {
    if (proxyEnabled) {
      return 'RAWG + Steam (via serveur, rapide sur le web)';
    }
    if (RawgService.isConfigured) {
      return 'RAWG (clé API locale)';
    }
    return 'Configure RAWG_API_KEY ou Supabase pour la recherche';
  }

  static String? get lastError => RawgService.lastSearchError;

  static Future<List<Map<String, String>>> search(String query) async {
    return RawgService.search(query);
  }
}
