import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Métadonnées manga via MangaDex (tomes sortis + couvertures par volume).
abstract final class MangaDexService {
  static const _base = 'https://api.mangadex.org';

  static Future<MangaDexSeriesMeta?> lookupManga(String query) async {
    final q = query.trim();
    if (q.length < 2) return null;
    try {
      final searchUri = Uri.parse('$_base/manga').replace(queryParameters: {
        'title': q,
        'limit': '5',
        'order[relevance]': 'desc',
        'includes[]': 'cover_art',
      });
      final searchRes = await http
          .get(searchUri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (searchRes.statusCode != 200) return null;
      final body = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? const [];
      if (data.isEmpty) return null;
      final manga = data.first as Map<String, dynamic>;
      final mangaId = manga['id']?.toString();
      if (mangaId == null) return null;

      final attrs = manga['attributes'] as Map<String, dynamic>? ?? {};
      final titles = attrs['title'] as Map<String, dynamic>? ?? {};
      final title = (titles['en'] ??
              titles['ja-ro'] ??
              (titles.isEmpty ? null : titles.values.first) ??
              q)
          .toString();

      final covers = await _fetchCovers(mangaId);
      final volumes = covers.keys.where((k) => k > 0).toList()..sort();
      final lastVol = volumes.isEmpty ? null : volumes.last;
      final coverUrl = covers[1] ??
          (volumes.isNotEmpty ? covers[volumes.first] : null) ??
          _coverFromRelationships(manga);

      return MangaDexSeriesMeta(
        id: mangaId,
        title: title,
        volumesPublished: lastVol,
        coverByVolume: covers,
        seriesCoverUrl: coverUrl,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('MangaDex lookup: $e');
      return null;
    }
  }

  static Future<Map<int, String>> _fetchCovers(String mangaId) async {
    final out = <int, String>{};
    try {
      final uri = Uri.parse('$_base/cover').replace(queryParameters: {
        'manga[]': mangaId,
        'limit': '100',
        'order[volume]': 'asc',
      });
      final res = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return out;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? const [];
      for (final raw in data) {
        final item = raw as Map<String, dynamic>;
        final attrs = item['attributes'] as Map<String, dynamic>? ?? {};
        final fileName = attrs['fileName']?.toString();
        final volRaw = attrs['volume']?.toString();
        if (fileName == null || fileName.isEmpty) continue;
        final vol = int.tryParse(volRaw ?? '') ?? 0;
        if (vol <= 0) continue;
        out.putIfAbsent(
          vol,
          () => 'https://uploads.mangadex.org/covers/$mangaId/$fileName.256.jpg',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MangaDex covers: $e');
    }
    return out;
  }

  static String? _coverFromRelationships(Map<String, dynamic> manga) {
    final rels = manga['relationships'] as List<dynamic>? ?? const [];
    for (final r in rels) {
      final rel = r as Map<String, dynamic>;
      if (rel['type'] != 'cover_art') continue;
      final attrs = rel['attributes'] as Map<String, dynamic>?;
      final fileName = attrs?['fileName']?.toString();
      final id = manga['id']?.toString();
      if (fileName == null || id == null) continue;
      return 'https://uploads.mangadex.org/covers/$id/$fileName.256.jpg';
    }
    return null;
  }
}

class MangaDexSeriesMeta {
  final String id;
  final String title;
  final int? volumesPublished;
  final Map<int, String> coverByVolume;
  final String? seriesCoverUrl;

  const MangaDexSeriesMeta({
    required this.id,
    required this.title,
    this.volumesPublished,
    this.coverByVolume = const {},
    this.seriesCoverUrl,
  });
}
