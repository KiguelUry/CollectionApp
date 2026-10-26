import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/book_series_normalizer.dart';
import '../utils/book_title_parser.dart';
import '../utils/book_vf_edition.dart';
import '../utils/catalog_http.dart';
import '../utils/web_catalog_proxy.dart';

/// Recherche livres / mangas / BD — API iTunes (couvertures HD).
/// Sur le web : Edge Function Supabase `catalog-proxy` (CORS).
class ItunesBooksService {
  static Future<List<Map<String, String>>> search(
    String query, {
    int limit = 25,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    final ebook = await _searchEntity(q, entity: 'ebook', limit: limit);
    if (ebook.length >= 8) return ebook;

    final merged = <Map<String, String>>[];
    final seen = <String>{};
    for (final hit in [
      ...ebook,
      ...await _searchEntity(q, entity: 'audiobook', limit: 12),
    ]) {
      final key = (hit['title'] ?? '').toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      merged.add(hit);
    }
    return merged.take(limit).toList();
  }

  static Future<Map<String, String>?> lookupByIsbn(String isbn) async {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length < 10) return null;
    final hits = await search(cleaned, limit: 5);
    if (hits.isEmpty) return null;
    return hits.first;
  }

  /// Fallback VF (Kana / Glénat / Crunchyroll) : couverture + date FR.
  /// Requête : `"$seriesName Tome $volume"` · country=FR.
  static Future<Map<String, String>?> lookupFrenchVolume(
    String seriesName,
    int volume,
  ) async {
    final name = seriesName.trim();
    if (name.length < 2 || volume < 1) return null;
    final term = '$name Tome $volume';
    final hits = await search(term, limit: 10);
    if (hits.isEmpty) return null;

    Map<String, String>? best;
    var bestScore = -1;
    for (final h in hits) {
      final title = h['title'] ?? '';
      if (title.isEmpty) continue;
      // Zéro édition US VIZ (« Vol. N »).
      if (BookVfEdition.isUsVolTitle(title)) continue;
      if (!BookVfEdition.isFrenchEdition(
        title: title,
        language: h['language'],
        source: h['source'],
      )) {
        continue;
      }
      // Doit appartenir à la série et matcher le n° de tome.
      if (!BookSeriesNormalizer.hitBelongsToSeries(title, name) &&
          !BookSeriesNormalizer.normalizeKey(title).contains(
                BookSeriesNormalizer.normalizeKey(name),
              )) {
        continue;
      }
      final volOk = BookTitleParser.titleMatchesVolumeExactly(title, volume) ||
          BookTitleParser.extractVolumeNumberStrict(title) == volume;
      if (!volOk) continue;
      // Préfère les titres « Tome N » (VF) aux formats anglo.
      var score = RegExp(r'\btome\s*\d+', caseSensitive: false).hasMatch(title)
          ? 20
          : 5;
      if ((h['image_url'] ?? '').isNotEmpty) score += 5;
      if ((h['published_date'] ?? '').isNotEmpty) score += 5;
      if (score > bestScore) {
        bestScore = score;
        best = h;
      }
    }
    return best;
  }

  /// Enrichit plusieurs tomes (lots de 4) — couvertures / dates FR manquantes.
  static Future<Map<int, Map<String, String>>> lookupFrenchVolumesBatch(
    String seriesName,
    Iterable<int> volumes,
  ) async {
    final out = <int, Map<String, String>>{};
    final list = volumes.where((v) => v > 0).toSet().toList()..sort();
    for (var i = 0; i < list.length; i += 4) {
      final chunk = list.skip(i).take(4).toList();
      final results = await Future.wait(
        chunk.map((n) => lookupFrenchVolume(seriesName, n)),
      );
      for (var j = 0; j < chunk.length; j++) {
        final hit = results[j];
        if (hit != null) out[chunk[j]] = hit;
      }
      if (i + 4 < list.length) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    return out;
  }

  static Future<List<Map<String, String>>> _searchEntity(
    String query, {
    required String entity,
    required int limit,
  }) async {
    try {
      final itunesUri = Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'media': 'ebook',
        'entity': entity,
        'limit': '$limit',
        'country': 'FR',
        'lang': 'fr_fr',
      });
      final response = await http
          .get(
            proxiedCatalogUri(itunesUri),
            headers: {
              ...catalogHttpHeaders,
              ...proxiedCatalogHeaders(),
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('iTunes books ${response.statusCode}: ${response.body}');
        }
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['results'] as List<dynamic>? ?? [];

      return list
          .map((raw) => _mapBook(raw as Map<String, dynamic>))
          .whereType<Map<String, String>>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('iTunes books search: $e');
      return [];
    }
  }

  static Map<String, String>? _mapBook(Map<String, dynamic> m) {
    final title =
        m['trackName']?.toString() ?? m['collectionName']?.toString();
    if (title == null || title.isEmpty) return null;
    // Rejette pollution US VIZ (« Kagurabachi, Vol. 10 »).
    if (BookVfEdition.isUsVolTitle(title)) return null;

    final author = m['artistName']?.toString() ?? '';
    final series = m['collectionName']?.toString();
    if (series != null && BookVfEdition.isUsVolTitle(series)) return null;
    final imageUrl = _hdArtwork(
      m['artworkUrl600']?.toString() ?? m['artworkUrl100']?.toString() ?? '',
    );

    final release = m['releaseDate']?.toString();
    final yearStr =
        release != null && release.length >= 4 ? release.substring(0, 4) : '';

    // country=FR → on marque language=fr pour les dates À paraître.
    final result = <String, String>{
      'title': title,
      'author': author,
      'year': yearStr,
      'image_url': imageUrl,
      'itunes_id': m['trackId']?.toString() ?? '',
      'source': 'itunes',
      'language': 'fr',
      if (release != null && release.isNotEmpty) 'published_date': release,
    };

    if (series != null &&
        series.isNotEmpty &&
        series.toLowerCase() != title.toLowerCase()) {
      result['series_title'] = series;
    }

    final genres = m['genres'] as List<dynamic>?;
    if (genres != null && genres.isNotEmpty) {
      result['genre'] = genres.first.toString();
    }

    return result;
  }

  static String _hdArtwork(String url) {
    if (url.isEmpty) return '';
    return url
        .replaceFirst('100x100bb', '600x600bb')
        .replaceFirst('60x60bb', '600x600bb')
        .replaceFirst('http://', 'https://');
  }
}
