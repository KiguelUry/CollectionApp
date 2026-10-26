import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/book_series_normalizer.dart';
import '../utils/web_catalog_proxy.dart';

/// Métadonnées manga via MangaDex (sans clé).
/// Sur le web : Edge Function `catalog-proxy` (CORS).
/// 1 recherche + 1–N pages `/cover` → tous les tomes + couvertures HD.
abstract final class MangaDexService {
  static const _base = 'https://api.mangadex.org';
  static const _uploads = 'https://uploads.mangadex.org';

  /// Tags MangaDex à exclure (fan-colored, doujinshi).
  static const _excludedTagIds = [
    '7b2ce280-79ef-4c09-9b5a-a839f0764984', // Fan Colored
    'b13b2a48-c720-44a9-9c77-39c9905739b0', // Doujinshi
  ];

  static Future<MangaDexSeriesMeta?> lookupManga(
    String query, {
    String? authorHint,
  }) async {
    final results = await searchManga(query, authorHint: authorHint, limit: 1);
    return results.isEmpty ? null : results.first;
  }

  static Future<List<MangaDexSeriesMeta>> searchManga(
    String query, {
    String? authorHint,
    int limit = 5,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      // Récupère un peu plus pour filtrer/trier côté client.
      final fetchLimit = (limit.clamp(1, 10) * 3).clamp(5, 15);
      final params = StringBuffer(
        '$_base/manga?title=${Uri.encodeQueryComponent(q)}'
        '&limit=$fetchLimit'
        '&order[followedCount]=desc'
        '&order[relevance]=desc'
        '&originalLanguage[]=ja'
        '&contentRating[]=safe'
        '&contentRating[]=suggestive'
        '&includes[]=author'
        '&includes[]=cover_art'
        '&includes[]=artist',
      );
      for (final tagId in _excludedTagIds) {
        params.write('&excludedTags[]=$tagId');
      }
      final withIncludes = Uri.parse(params.toString());
      final searchRes = await http
          .get(
            proxiedCatalogUri(withIncludes),
            headers: proxiedCatalogHeaders(),
          )
          .timeout(const Duration(seconds: 20));
      if (searchRes.statusCode != 200) return const [];
      final body = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? const [];

      final scored = <({MangaDexSeriesMeta meta, double score})>[];
      for (final raw in data) {
        if (raw is! Map<String, dynamic>) continue;
        // Filtrage local STRICT (l'API ignore souvent excludedTags).
        if (isParasiteMangaEntry(raw)) continue;
        final meta = await _mapManga(raw, q, authorHint);
        if (meta == null) continue;
        if (looksLikeParasiteTitle(meta.title)) continue;
        scored.add((meta: meta, score: _rankScore(raw, meta, q)));
      }
      // Exact match (insensible à la casse) toujours en tête absolue.
      scored.sort((a, b) {
        final aExact = _hasExactTitleMatch(a.meta, q);
        final bExact = _hasExactTitleMatch(b.meta, q);
        if (aExact != bExact) return aExact ? -1 : 1;
        return b.score.compareTo(a.score);
      });
      return scored.take(limit.clamp(1, 10)).map((e) => e.meta).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('MangaDex search: $e');
      return const [];
    }
  }

  /// Mots parasites (Bonus, Fan Colored, Colored, Doujinshi, Anthology, Side Story).
  static final _parasiteTitleRe = RegExp(
    r'\b(?:bonus|fan\s*colou?red|colou?red|doujinshi|anthology|side\s*story)\b',
    caseSensitive: false,
  );

  /// Exposé pour tests / réutilisation.
  static bool looksLikeParasiteTitle(String title) {
    final t = title.trim();
    if (t.isEmpty) return false;
    return _parasiteTitleRe.hasMatch(t);
  }

  /// Filtre Dart post-JSON : titres EN/JA/romaji + tags.
  static bool isParasiteMangaEntry(Map<String, dynamic> manga) {
    final attrs = manga['attributes'] as Map<String, dynamic>? ?? {};
    final titles = attrs['title'] as Map<String, dynamic>? ?? {};
    final altTitles = attrs['altTitles'] as List<dynamic>? ?? const [];
    final blobs = <String>[
      ...titles.values.map((v) => v?.toString() ?? ''),
      for (final alt in altTitles)
        if (alt is Map)
          for (final v in alt.values) v?.toString() ?? '',
    ];
    for (final blob in blobs) {
      if (looksLikeParasiteTitle(blob)) return true;
    }
    final tags = attrs['tags'] as List<dynamic>? ?? const [];
    for (final t in tags) {
      if (t is! Map) continue;
      final id = t['id']?.toString() ?? '';
      if (_excludedTagIds.contains(id)) return true;
      final name = (t['attributes'] as Map?)?['name'];
      if (name is Map) {
        final en = (name['en'] ?? '').toString();
        if (looksLikeParasiteTitle(en)) return true;
      }
    }
    return false;
  }

  static bool _hasExactTitleMatch(MangaDexSeriesMeta meta, String query) {
    final qKey = BookSeriesNormalizer.normalizeKey(query);
    if (qKey.isEmpty) return false;
    return BookSeriesNormalizer.normalizeKey(meta.title) == qKey;
  }

  /// Exact match ≫ startsWith ≫ contains ; bonus volumes / covers.
  static double _rankScore(
    Map<String, dynamic> raw,
    MangaDexSeriesMeta meta,
    String query,
  ) {
    final qKey = BookSeriesNormalizer.normalizeKey(query);
    final tKey = BookSeriesNormalizer.normalizeKey(meta.title);
    var score = 0.0;
    if (tKey == qKey) {
      score += 10000;
    } else if (tKey.startsWith(qKey) || qKey.startsWith(tKey)) {
      score += 500;
    } else if (tKey.contains(qKey) || qKey.contains(tKey)) {
      score += 200;
    }
    // Pénalise les spin-offs / sous-titres longs même sans mot parasite.
    if (meta.title.contains(':') || meta.title.contains(' - ')) {
      score -= 80;
    }
    final attrs = raw['attributes'] as Map<String, dynamic>? ?? {};
    final status = (attrs['status'] ?? '').toString();
    if (status == 'ongoing' || status == 'completed') score += 50;
    final year = attrs['year'];
    if (year is int && year >= 2000) score += 10;
    final vols = meta.volumesPublished ?? 0;
    score += vols.clamp(0, 200).toDouble();
    score += meta.coverByVolume.length.clamp(0, 100).toDouble();
    return score;
  }

  static Future<MangaDexSeriesMeta?> _mapManga(
    Map<String, dynamic> manga,
    String query,
    String? authorHint,
  ) async {
    final mangaId = manga['id']?.toString();
    if (mangaId == null) return null;

    final attrs = manga['attributes'] as Map<String, dynamic>? ?? {};
    final titles = attrs['title'] as Map<String, dynamic>? ?? {};
    final altTitles = attrs['altTitles'] as List<dynamic>? ?? const [];
    var title = (titles['en'] ??
            titles['ja-ro'] ??
            titles['ja'] ??
            (titles.isEmpty ? null : titles.values.first) ??
            query)
        .toString();
    // Préfère un altTitle FR / matching query.
    for (final alt in altTitles) {
      if (alt is! Map<String, dynamic>) continue;
      for (final e in alt.entries) {
        final t = e.value?.toString() ?? '';
        if (t.isEmpty) continue;
        if (BookSeriesNormalizer.hitBelongsToSeries(t, query) ||
            BookSeriesNormalizer.normalizeKey(t) ==
                BookSeriesNormalizer.normalizeKey(query)) {
          title = t;
          break;
        }
      }
    }
    title = BookSeriesNormalizer.displaySeriesName(title);

    // Filtre homonymes trop éloignés.
    final qKey = BookSeriesNormalizer.normalizeKey(query);
    final tKey = BookSeriesNormalizer.normalizeKey(title);
    if (tKey != qKey &&
        !tKey.contains(qKey) &&
        !qKey.contains(tKey) &&
        !BookSeriesNormalizer.hitBelongsToSeries(title, query)) {
      // Accepte si un altTitle matche.
      var ok = false;
      for (final alt in altTitles) {
        if (alt is! Map) continue;
        for (final v in alt.values) {
          final t = v?.toString() ?? '';
          if (BookSeriesNormalizer.normalizeKey(t).contains(qKey) ||
              qKey.contains(BookSeriesNormalizer.normalizeKey(t))) {
            ok = true;
            break;
          }
        }
      }
      if (!ok) return null;
    }

    String? author;
    final rels = manga['relationships'] as List<dynamic>? ?? const [];
    for (final r in rels) {
      if (r is! Map<String, dynamic>) continue;
      if (r['type'] != 'author' && r['type'] != 'artist') continue;
      final a = r['attributes'] as Map<String, dynamic>?;
      final name = a?['name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        author = name;
        break;
      }
    }
    if (authorHint != null &&
        authorHint.trim().isNotEmpty &&
        author != null &&
        !BookSeriesNormalizer.authorsMatch(author, authorHint)) {
      // Garde quand même si le titre matche exactement (auteur API parfois différent).
      if (tKey != qKey) return null;
    }

    final covers = await fetchAllCovers(mangaId);
    final volumes = covers.keys.where((k) => k > 0).toList()..sort();
    final lastVol = volumes.isEmpty ? null : volumes.last;
    final coverUrl = covers[1] ??
        (volumes.isNotEmpty ? covers[volumes.first] : null) ??
        _coverFromRelationships(manga, mangaId);

    return MangaDexSeriesMeta(
      id: mangaId,
      title: title,
      author: author,
      volumesPublished: lastVol,
      coverByVolume: covers,
      seriesCoverUrl: coverUrl,
    );
  }

  /// Toutes les couvertures (paginé si >100, ex. One Piece 114).
  static Future<Map<int, String>> fetchAllCovers(String mangaId) async {
    final best = <int, _CoverPick>{};
    var offset = 0;
    const pageSize = 100;
    for (var page = 0; page < 5; page++) {
      try {
        final uri = Uri.parse(
          '$_base/cover?manga[]=${Uri.encodeQueryComponent(mangaId)}'
          '&limit=$pageSize'
          '&offset=$offset'
          '&order[volume]=asc',
        );
        final res = await http
            .get(
              proxiedCatalogUri(uri),
              headers: proxiedCatalogHeaders(),
            )
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) break;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as List<dynamic>? ?? const [];
        final total = body['total'] is int
            ? body['total'] as int
            : int.tryParse('${body['total']}') ?? 0;

        for (final raw in data) {
          if (raw is! Map<String, dynamic>) continue;
          final attrs = raw['attributes'] as Map<String, dynamic>? ?? {};
          final fileName = attrs['fileName']?.toString();
          final volRaw = attrs['volume']?.toString();
          if (fileName == null || fileName.isEmpty) continue;
          final vol = int.tryParse(volRaw ?? '') ?? 0;
          if (vol <= 0) continue;
          final locale = (attrs['locale'] ?? '').toString().toLowerCase();
          final score = _localeScore(locale);
          final url = '$_uploads/covers/$mangaId/$fileName.512.jpg';
          final prev = best[vol];
          if (prev == null || score > prev.score) {
            best[vol] = _CoverPick(url: url, score: score);
          }
        }

        offset += pageSize;
        if (data.length < pageSize || offset >= total) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        if (kDebugMode) debugPrint('MangaDex covers page $page: $e');
        break;
      }
    }
    return {for (final e in best.entries) e.key: e.value.url};
  }

  /// fr > ja > en > autres.
  static int _localeScore(String locale) {
    if (locale.startsWith('fr')) return 40;
    if (locale.startsWith('ja')) return 30;
    if (locale.startsWith('en')) return 20;
    return 10;
  }

  static String? _coverFromRelationships(
    Map<String, dynamic> manga,
    String mangaId,
  ) {
    final rels = manga['relationships'] as List<dynamic>? ?? const [];
    for (final r in rels) {
      if (r is! Map<String, dynamic>) continue;
      if (r['type'] != 'cover_art') continue;
      final attrs = r['attributes'] as Map<String, dynamic>?;
      final fileName = attrs?['fileName']?.toString();
      if (fileName == null) continue;
      return '$_uploads/covers/$mangaId/$fileName.512.jpg';
    }
    return null;
  }
}

class _CoverPick {
  final String url;
  final int score;
  const _CoverPick({required this.url, required this.score});
}

class MangaDexSeriesMeta {
  final String id;
  final String title;
  final String? author;
  final int? volumesPublished;
  final Map<int, String> coverByVolume;
  final String? seriesCoverUrl;

  const MangaDexSeriesMeta({
    required this.id,
    required this.title,
    this.author,
    this.volumesPublished,
    this.coverByVolume = const {},
    this.seriesCoverUrl,
  });
}
