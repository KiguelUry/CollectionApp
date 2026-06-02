import '../models/category_metadata.dart';
import 'discogs_service.dart';
import 'musicbrainz_service.dart';

/// Vinyles / CD : Discogs en priorité (si token), sinon MusicBrainz.
class MediaCatalogService {
  static bool get discogsEnabled => DiscogsService.isConfigured;

  static String catalogLabel({MediaFormat? format}) {
    if (!discogsEnabled) return 'MusicBrainz · sans clé API';
    if (format == MediaFormat.vinyl) {
      return 'Discogs (vinyles) + MusicBrainz';
    }
    return 'Discogs + MusicBrainz';
  }

  static Future<List<Map<String, String>>> searchReleases(
    String query, {
    MediaFormat format = MediaFormat.vinyl,
    int limit = 20,
  }) async {
    return searchReleasesAdvanced(
      format: format,
      limit: limit,
      query: query,
    );
  }

  /// Recherche par titre, artiste, ou les deux combinés.
  static Future<List<Map<String, String>>> searchReleasesAdvanced({
    MediaFormat format = MediaFormat.vinyl,
    int limit = 20,
    String? query,
    String? artist,
    String? title,
  }) async {
    final parts = <String>[
      if (artist != null && artist.trim().isNotEmpty) artist.trim(),
      if (title != null && title.trim().isNotEmpty) title.trim(),
    ];
    if (parts.isEmpty && query != null && query.trim().isNotEmpty) {
      parts.add(query.trim());
    }
    final q = parts.join(' ');
    if (q.length < 2) return [];

    if (discogsEnabled) {
      final discogs = await DiscogsService.searchReleases(
        q,
        format: format,
        limit: limit,
      );
      if (discogs.isNotEmpty) return discogs;
    }

    return MusicbrainzService.searchReleases(q, limit: limit);
  }

  static Future<Map<String, String>?> lookupByBarcode(
    String barcode, {
    MediaFormat format = MediaFormat.vinyl,
  }) async {
    if (discogsEnabled) {
      final discogs = await DiscogsService.lookupByBarcode(
        barcode,
        format: format,
      );
      if (discogs != null) return discogs;
    }
    return MusicbrainzService.lookupByBarcode(barcode);
  }

  static Map<String, dynamic> metadataFromLookup(
    Map<String, String> album,
    MediaFormat format,
  ) {
    return {
      'format': format.dbValue,
      if ((album['artist'] ?? '').isNotEmpty) 'artist': album['artist']!,
      if ((album['year'] ?? '').isNotEmpty) 'year': album['year']!,
      if ((album['barcode'] ?? '').isNotEmpty) 'barcode': album['barcode']!,
      if ((album['label'] ?? '').isNotEmpty) 'label': album['label']!,
      if ((album['catalog_number'] ?? '').isNotEmpty)
        'catalog_number': album['catalog_number']!,
      if ((album['country'] ?? '').isNotEmpty) 'country': album['country']!,
      if ((album['pressing_format'] ?? '').isNotEmpty)
        'pressing_format': album['pressing_format']!,
      if ((album['musicbrainz_release_id'] ?? '').isNotEmpty)
        'musicbrainz_release_id': album['musicbrainz_release_id']!,
      if ((album['discogs_release_id'] ?? '').isNotEmpty)
        'discogs_release_id': album['discogs_release_id']!,
      'catalog_source': album['source'] ?? 'musicbrainz',
    };
  }
}
