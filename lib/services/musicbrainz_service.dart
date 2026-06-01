import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// MusicBrainz + Cover Art Archive (gratuit, sans clé).
/// https://musicbrainz.org/doc/MusicBrainz_API
class MusicbrainzService {
  static const _userAgent = 'Collectingo/1.0 (collection-app; contact@collectingo.app)';

  static Future<List<Map<String, String>>> searchReleases(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final url = Uri.https('musicbrainz.org', '/ws/2/release', {
        'query': q,
        'fmt': 'json',
        'limit': '$limit',
      });
      final response = await http.get(
        url,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final releases = data['releases'] as List<dynamic>? ?? [];
      final out = <Map<String, String>>[];
      for (final raw in releases) {
        final mapped = await _mapRelease(raw as Map<String, dynamic>);
        if (mapped != null) out.add(mapped);
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('MusicBrainz search: $e');
      return [];
    }
  }

  /// Code-barres EAN (vinyle / CD).
  static Future<Map<String, String>?> lookupByBarcode(String barcode) async {
    final cleaned = barcode.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length < 8) return null;

    try {
      final url = Uri.https('musicbrainz.org', '/ws/2/release', {
        'query': 'barcode:$cleaned',
        'fmt': 'json',
        'limit': '5',
      });
      final response = await http.get(
        url,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final releases = data['releases'] as List<dynamic>? ?? [];
      for (final raw in releases) {
        final mapped = await _mapRelease(raw as Map<String, dynamic>);
        if (mapped != null) {
          mapped['barcode'] = cleaned;
          return mapped;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MusicBrainz barcode: $e');
    }
    return null;
  }

  static Future<Map<String, String>?> _mapRelease(
    Map<String, dynamic> release,
  ) async {
    final title = release['title'] as String?;
    if (title == null || title.isEmpty) return null;

    final id = release['id'] as String?;
    final date = release['date'] as String? ?? '';
    final year = date.length >= 4 ? date.substring(0, 4) : date;

    final credits = release['artist-credit'] as List<dynamic>? ?? [];
    final artist = credits.isNotEmpty
        ? ((credits.first as Map)['name'] as String? ?? '')
        : '';

    final country = release['country'] as String? ?? '';
    final status = release['status'] as String? ?? '';

    String imageUrl = '';
    if (id != null) {
      imageUrl = await _fetchCoverUrl(id) ?? '';
    }

    return {
      'title': title,
      'artist': artist,
      'year': year,
      'image_url': imageUrl,
      'musicbrainz_release_id': id ?? '',
      if (country.isNotEmpty) 'country': country,
      if (status.isNotEmpty) 'release_status': status,
      'source': 'musicbrainz',
    };
  }

  static Future<String?> _fetchCoverUrl(String releaseId) async {
    try {
      final url = Uri.https(
        'coverartarchive.org',
        '/release/$releaseId/front',
      );
      final response = await http.head(
        url,
        headers: {'User-Agent': _userAgent},
      );
      if (response.statusCode == 307 || response.statusCode == 200) {
        return response.headers['location'] ??
            'https://coverartarchive.org/release/$releaseId/front-500';
      }
      if (response.statusCode == 404) return null;
      return 'https://coverartarchive.org/release/$releaseId/front-500';
    } catch (_) {
      return null;
    }
  }
}
