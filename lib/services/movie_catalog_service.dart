import 'itunes_movie_service.dart';
import 'tmdb_service.dart';

/// Films physiques (Blu-ray, DVD…) — TMDB si clé, sinon iTunes (gratuit).
class MovieCatalogService {
  static bool get tmdbEnabled => TmdbService.isConfigured;

  static String get catalogLabel {
    if (tmdbEnabled) {
      return 'TMDB (films) · secours iTunes sans clé';
    }
    return 'iTunes (gratuit, sans clé API)';
  }

  /// Films uniquement (pas de séries TV).
  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    if (tmdbEnabled) {
      final tmdb = await TmdbService.searchMovies(q);
      if (tmdb.isNotEmpty) return tmdb;
    }

    return ItunesMovieService.search(q);
  }
}
