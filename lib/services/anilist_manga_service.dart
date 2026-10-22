import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Métadonnées manga via AniList GraphQL (gratuit, sans clé).
abstract final class AnilistMangaService {
  static const _endpoint = 'https://graphql.anilist.co';

  static Future<int?> estimateVolumeCount(String seriesName) async {
    final meta = await lookupManga(seriesName);
    return meta?.volumes;
  }

  static Future<AnilistMangaMeta?> lookupManga(String query) async {
    final q = query.trim();
    if (q.length < 2) return null;
    const gql = r'''
query ($search: String) {
  Media(search: $search, type: MANGA, sort: SEARCH_MATCH) {
    id
    title { romaji english native }
    volumes
    chapters
    coverImage { large extraLarge }
    averageScore
    status
  }
}
''';
    try {
      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query': gql,
              'variables': {'search': q},
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final media = data?['data']?['Media'] as Map<String, dynamic>?;
      if (media == null) return null;
      final titleMap = media['title'] as Map<String, dynamic>? ?? {};
      final title = (titleMap['english'] ??
              titleMap['romaji'] ??
              titleMap['native'] ??
              q)
          .toString();
      final cover = media['coverImage'] as Map<String, dynamic>?;
      final coverUrl = (cover?['extraLarge'] ?? cover?['large'])?.toString();
      final volumes = media['volumes'] is int
          ? media['volumes'] as int
          : int.tryParse('${media['volumes'] ?? ''}');
      final scoreRaw = media['averageScore'];
      final score100 = scoreRaw is num
          ? scoreRaw.toDouble()
          : double.tryParse('$scoreRaw');
      // AniList score 0–100 → /5
      final ratingOnFive =
          score100 != null && score100 > 0 ? score100 / 20.0 : null;
      return AnilistMangaMeta(
        title: title,
        volumes: volumes != null && volumes > 0 ? volumes : null,
        coverUrl: coverUrl,
        ratingOnFive: ratingOnFive,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('AniList lookup: $e');
      return null;
    }
  }
}

class AnilistMangaMeta {
  final String title;
  final int? volumes;
  final String? coverUrl;
  final double? ratingOnFive;

  const AnilistMangaMeta({
    required this.title,
    this.volumes,
    this.coverUrl,
    this.ratingOnFive,
  });
}
