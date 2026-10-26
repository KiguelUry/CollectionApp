import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/book_series_normalizer.dart';

/// Métadonnées manga via AniList GraphQL (gratuit, sans clé).
abstract final class AnilistMangaService {
  static const _endpoint = 'https://graphql.anilist.co';

  static Future<int?> estimateVolumeCount(String seriesName) async {
    final meta = await lookupManga(seriesName);
    return meta?.volumes;
  }

  static Future<AnilistMangaMeta?> lookupManga(String query) async {
    final results = await searchManga(query, limit: 1);
    return results.isEmpty ? null : results.first;
  }

  /// Recherche multi-résultats (bannières recherche livres).
  static Future<List<AnilistMangaMeta>> searchManga(
    String query, {
    int limit = 5,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    const gql = r'''
query ($search: String, $perPage: Int) {
  Page(page: 1, perPage: $perPage) {
    media(search: $search, type: MANGA, sort: SEARCH_MATCH) {
      id
      title { romaji english native }
      volumes
      chapters
      coverImage { large extraLarge }
      averageScore
      status
      staff(sort: RELEVANCE, perPage: 8) {
        edges {
          role
          node { name { full native } }
        }
      }
    }
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
              'variables': {
                'search': q,
                'perPage': limit.clamp(1, 10),
              },
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final page = data?['data']?['Page'] as Map<String, dynamic>?;
      final mediaList = page?['media'] as List<dynamic>? ?? const [];
      final out = <AnilistMangaMeta>[];
      for (final raw in mediaList) {
        if (raw is! Map<String, dynamic>) continue;
        final meta = _mapMedia(raw, q);
        if (meta != null) out.add(meta);
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('AniList search: $e');
      return const [];
    }
  }

  static AnilistMangaMeta? _mapMedia(Map<String, dynamic> media, String q) {
    final titleMap = media['title'] as Map<String, dynamic>? ?? {};
    final title = (titleMap['english'] ??
            titleMap['romaji'] ??
            titleMap['native'] ??
            q)
        .toString();
    // Rejette les homonymes trop éloignés (ex. « Fallen Kingdom » pour « kingdom »).
    if (!BookSeriesNormalizer.hitBelongsToSeries(title, q) &&
        !BookSeriesNormalizer.normalizeKey(title)
            .contains(BookSeriesNormalizer.normalizeKey(q)) &&
        !BookSeriesNormalizer.normalizeKey(q)
            .contains(BookSeriesNormalizer.normalizeKey(title))) {
      // Accepte si la clé query est égale au romaji/english nettoyé.
      final romaji = titleMap['romaji']?.toString() ?? '';
      final english = titleMap['english']?.toString() ?? '';
      final qKey = BookSeriesNormalizer.normalizeKey(q);
      final ok = BookSeriesNormalizer.normalizeKey(romaji) == qKey ||
          BookSeriesNormalizer.normalizeKey(english) == qKey ||
          BookSeriesNormalizer.normalizeKey(
                BookSeriesNormalizer.displaySeriesName(title),
              ) ==
              qKey;
      if (!ok) return null;
    }

    final cover = media['coverImage'] as Map<String, dynamic>?;
    final coverUrl = (cover?['extraLarge'] ?? cover?['large'])?.toString();
    final volumes = media['volumes'] is int
        ? media['volumes'] as int
        : int.tryParse('${media['volumes'] ?? ''}');
    final scoreRaw = media['averageScore'];
    final score100 = scoreRaw is num
        ? scoreRaw.toDouble()
        : double.tryParse('$scoreRaw');
    final ratingOnFive =
        score100 != null && score100 > 0 ? score100 / 20.0 : null;

    String? author;
    final staff = media['staff'] as Map<String, dynamic>?;
    final edges = staff?['edges'] as List<dynamic>? ?? const [];
    for (final edge in edges) {
      if (edge is! Map<String, dynamic>) continue;
      final role = (edge['role'] ?? '').toString().toLowerCase();
      if (!role.contains('story') &&
          !role.contains('art') &&
          !role.contains('author') &&
          !role.contains('creator')) {
        continue;
      }
      final node = edge['node'] as Map<String, dynamic>?;
      final name = node?['name'] as Map<String, dynamic>?;
      final full = (name?['full'] ?? name?['native'])?.toString().trim();
      if (full != null && full.isNotEmpty) {
        author = full;
        break;
      }
    }
    // Fallback : premier staff.
    if (author == null) {
      for (final edge in edges) {
        if (edge is! Map<String, dynamic>) continue;
        final node = edge['node'] as Map<String, dynamic>?;
        final name = node?['name'] as Map<String, dynamic>?;
        final full = (name?['full'] ?? name?['native'])?.toString().trim();
        if (full != null && full.isNotEmpty) {
          author = full;
          break;
        }
      }
    }

    return AnilistMangaMeta(
      title: BookSeriesNormalizer.displaySeriesName(title),
      volumes: volumes != null && volumes > 0 ? volumes : null,
      coverUrl: coverUrl,
      ratingOnFive: ratingOnFive,
      author: author,
      anilistId: media['id'] is int ? media['id'] as int : null,
    );
  }
}

class AnilistMangaMeta {
  final String title;
  final int? volumes;
  final String? coverUrl;
  final double? ratingOnFive;
  final String? author;
  final int? anilistId;

  const AnilistMangaMeta({
    required this.title,
    this.volumes,
    this.coverUrl,
    this.ratingOnFive,
    this.author,
    this.anilistId,
  });
}
