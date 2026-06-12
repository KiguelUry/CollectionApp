import 'rawg_service.dart';
import 'steam_store_service.dart';

/// Jeux vidéo — RAWG si clé, sinon catalogue Steam (gratuit).
class VideogameCatalogService {
  static bool get rawgEnabled => RawgService.isConfigured;

  static String get catalogLabel {
    if (rawgEnabled) {
      return 'RAWG · secours Steam sans clé';
    }
    return 'Steam (gratuit, sans clé API)';
  }

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    if (rawgEnabled) {
      final rawg = await RawgService.search(q);
      if (rawg.isNotEmpty) return rawg;
    }

    return SteamStoreService.search(q);
  }
}
