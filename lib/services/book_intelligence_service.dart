import '../models/book_subcategory.dart';
import '../utils/book_series_normalizer.dart';
import '../utils/book_title_parser.dart';
import 'anilist_manga_service.dart';
import 'google_books_service.dart';
import 'itunes_books_service.dart';
import 'open_library_service.dart';

/// Bannière série détectée dans les résultats de recherche.
class SeriesBannerCandidate {
  final String name;
  final int volumeCount;
  final Map<int, String> coversByVolume;

  const SeriesBannerCandidate({
    required this.name,
    required this.volumeCount,
    this.coversByVolume = const {},
  });
}

enum BookSearchField { title, author, publisher }

/// Filtres affinés pour la recherche catalogue.
class BookSearchFilters {
  final String titleQuery;
  final String authorQuery;
  final String publisherQuery;

  const BookSearchFilters({
    this.titleQuery = '',
    this.authorQuery = '',
    this.publisherQuery = '',
  });

  bool get isEmpty =>
      titleQuery.trim().isEmpty &&
      authorQuery.trim().isEmpty &&
      publisherQuery.trim().isEmpty;

  String get combinedQuery {
    final parts = [
      titleQuery.trim(),
      authorQuery.trim(),
    ].where((s) => s.isNotEmpty);
    return parts.join(' ');
  }
}

/// Résultat enrichi pour recherche / ajout livre.
class EnrichedBookHit {
  final Map<String, String> raw;
  final ParsedBookTitle parsed;
  final String displayTitle;
  final String? author;
  final String? publisher;
  final int? estimatedTotalVolumes;
  final double score;

  const EnrichedBookHit({
    required this.raw,
    required this.parsed,
    required this.displayTitle,
    this.author,
    this.publisher,
    this.estimatedTotalVolumes,
    required this.score,
  });

  String? get imageUrl {
    final u = raw['image_url'];
    if (u == null || u.isEmpty) return null;
    return u;
  }

  String? get authorPhotoUrl {
    final u = raw['author_photo_url'];
    if (u == null || u.isEmpty) return null;
    return u;
  }
}

/// Nettoie, parse et classe les résultats catalogue.
abstract final class BookIntelligenceService {
  static List<EnrichedBookHit> enrichAndRank(
    List<Map<String, String>> hits, {
    required BookSubcategory subcategory,
    BookSearchFilters filters = const BookSearchFilters(),
  }) {
    final enriched = hits.map((hit) => _enrich(hit, subcategory)).toList();

    final filtered = enriched.where((hit) {
      return _matchesFilters(hit, filters);
    }).toList();

    filtered.sort((a, b) => b.score.compareTo(a.score));

    final mainQ = filters.titleQuery.trim().toLowerCase();
    if (mainQ.isNotEmpty) {
      filtered.sort((a, b) {
        final sa = _queryMatchScore(a, mainQ);
        final sb = _queryMatchScore(b, mainQ);
        if (sa != sb) return sb.compareTo(sa);
        return b.score.compareTo(a.score);
      });
    }

    final deduped = dedupeBySeriesVolume(filtered);
    // Si le filtre titre a tout tué, garde les hits bruts dédupliqués.
    if (deduped.isEmpty && enriched.isNotEmpty) {
      return sortByVolumeThenScore(dedupeBySeriesVolume(enriched));
    }
    return sortByVolumeThenScore(deduped);
  }

  /// Déduplique par (série, n° tome) — priorise VF + vraie couverture,
  /// mais ne jette jamais le dernier hit d'un numéro de tome.
  static List<EnrichedBookHit> dedupeBySeriesVolume(
    List<EnrichedBookHit> hits,
  ) {
    if (hits.isEmpty) return hits;
    final best = <String, EnrichedBookHit>{};
    for (final h in hits) {
      final seriesKey = BookSeriesNormalizer.normalizeKey(
        h.parsed.seriesName ?? h.displayTitle,
      );
      final vol = h.parsed.volumeNumber?.round() ?? 0;
      final key = '$seriesKey|$vol';
      final prev = best[key];
      if (prev == null || _preferHit(h, prev)) {
        best[key] = h;
      }
    }
    return best.values.toList();
  }

  /// Tri tomes croissants, puis score.
  static List<EnrichedBookHit> sortByVolumeThenScore(
    List<EnrichedBookHit> hits,
  ) {
    final out = List<EnrichedBookHit>.from(hits);
    out.sort((a, b) {
      final va = a.parsed.volumeNumber;
      final vb = b.parsed.volumeNumber;
      if (va != null && vb != null && (va - vb).abs() > 0.01) {
        return va.compareTo(vb);
      }
      if (va != null && vb == null) return -1;
      if (va == null && vb != null) return 1;
      return b.score.compareTo(a.score);
    });
    return out;
  }

  static bool _preferHit(EnrichedBookHit a, EnrichedBookHit b) {
    final aCover = a.imageUrl != null && a.imageUrl!.isNotEmpty;
    final bCover = b.imageUrl != null && b.imageUrl!.isNotEmpty;
    if (aCover != bCover) return aCover;
    final aTitle = a.displayTitle.toLowerCase();
    final bTitle = b.displayTitle.toLowerCase();
    final aVf = aTitle.contains('tome') || aTitle.contains('t.');
    final bVf = bTitle.contains('tome') || bTitle.contains('t.');
    final aEn = aTitle.contains('vol.') || aTitle.contains('volume ');
    final bEn = bTitle.contains('vol.') || bTitle.contains('volume ');
    if (aVf && !bVf) return true;
    if (bVf && !aVf) return false;
    if (!aEn && bEn) return true;
    if (!bEn && aEn) return false;
    return a.score >= b.score;
  }

  /// Regroupe les hits en bannières multi-séries (Boruto / Thorgal…).
  static List<SeriesBannerCandidate> extractSeriesBanners(
    List<EnrichedBookHit> hits, {
    required String query,
    required BookSubcategory subcategory,
  }) {
    final groups = <String, _SeriesAgg>{};
    for (final h in hits) {
      final name = (h.parsed.seriesName ?? '').trim();
      if (name.length < 2) continue;
      final key = BookSeriesNormalizer.normalizeKey(name);
      final agg = groups.putIfAbsent(
        key,
        () => _SeriesAgg(displayName: name),
      );
      if (name.length > agg.displayName.length) agg.displayName = name;
      final n = h.parsed.volumeNumber?.round();
      if (n != null && n > 0) {
        if (n > agg.maxVol) agg.maxVol = n;
        final img = h.imageUrl;
        if (img != null && img.isNotEmpty) {
          agg.covers.putIfAbsent(n, () => img);
        }
      }
      final est = h.estimatedTotalVolumes;
      if (est != null && est > agg.maxVol) agg.maxVol = est;
    }

    // Si aucun groupe mais query utile → une bannière depuis le dictionnaire.
    if (groups.isEmpty && query.trim().length >= 2) {
      final dict = BookSeriesNormalizer.expectedCount(query, subcategory);
      final maxFromHits = hits
          .map((h) => h.parsed.volumeNumber?.round() ?? 0)
          .fold<int>(0, (a, b) => a > b ? a : b);
      final count = [
        dict ?? 0,
        maxFromHits,
      ].reduce((a, b) => a > b ? a : b);
      if (count > 0 || hits.isNotEmpty) {
        return [
          SeriesBannerCandidate(
            name: query.trim(),
            volumeCount: count > 0 ? count : (dict ?? 1),
          ),
        ];
      }
      return const [];
    }

    final qKey = BookSeriesNormalizer.normalizeKey(query);
    final banners = <SeriesBannerCandidate>[];
    for (final agg in groups.values) {
      final dict = BookSeriesNormalizer.expectedCount(
            agg.displayName,
            subcategory,
          ) ??
          0;
      final count = [agg.maxVol, dict].reduce((a, b) => a > b ? a : b);
      if (count < 1 && agg.covers.isEmpty) continue;
      banners.add(
        SeriesBannerCandidate(
          name: agg.displayName,
          volumeCount: count < 1 ? 1 : count,
          coversByVolume: Map<int, String>.from(agg.covers),
        ),
      );
    }
    banners.sort((a, b) {
      final aq = BookSeriesNormalizer.normalizeKey(a.name).contains(qKey);
      final bq = BookSeriesNormalizer.normalizeKey(b.name).contains(qKey);
      if (aq != bq) return aq ? -1 : 1;
      return b.volumeCount.compareTo(a.volumeCount);
    });
    // Garde les séries pertinentes (nom lié à la requête) + top.
    final relevant = banners.where((b) {
      final k = BookSeriesNormalizer.normalizeKey(b.name);
      return qKey.isEmpty ||
          k.contains(qKey) ||
          qKey.contains(k) ||
          k.split(' ').any((p) => p.length >= 4 && qKey.contains(p));
    }).toList();
    final use = relevant.isNotEmpty ? relevant : banners;
    return use.take(6).toList();
  }

  static EnrichedBookHit enrichSingle(
    Map<String, String> hit,
    BookSubcategory subcategory,
  ) =>
      _enrich(hit, subcategory);

  /// Requête catalogue pour un tome (ex. « Kagurabachi Tome 3 »).
  static String volumeSearchQuery(String seriesName, double volumeNumber) {
    final name = seriesName.trim();
    final vol = volumeNumber == volumeNumber.roundToDouble()
        ? volumeNumber.toInt().toString()
        : volumeNumber.toString();
    return '$name Tome $vol';
  }

  /// Couverture d'un tome via Google Books + iTunes (+ OL / AniList).
  static Future<String?> lookupVolumeCover({
    required String seriesName,
    required double volumeNumber,
    required BookSubcategory subcategory,
  }) async {
    final query = volumeSearchQuery(seriesName, volumeNumber);
    if (query.trim().length < 3) return null;

    // Tome 1 manga : couverture série AniList (HD) en priorité.
    if (subcategory == BookSubcategory.manga &&
        volumeNumber >= 0.99 &&
        volumeNumber < 1.01) {
      final ani = await AnilistMangaService.lookupManga(seriesName);
      if (ani?.coverUrl != null && ani!.coverUrl!.isNotEmpty) {
        return ani.coverUrl;
      }
    }

    final merged = <Map<String, String>>[];
    final seen = <String>{};
    for (final list in [
      await GoogleBooksService.search(query, maxResults: 12, langRestrict: 'fr'),
      await ItunesBooksService.search(query),
      await OpenLibraryService.searchBooks(query, subcategory: subcategory),
    ]) {
      for (final hit in list) {
        final title = hit['title']?.trim().toLowerCase() ?? '';
        if (title.isEmpty || !seen.add(title)) continue;
        merged.add(hit);
      }
    }

    final ranked = enrichAndRank(
      merged,
      subcategory: subcategory,
      filters: BookSearchFilters(titleQuery: query),
    );

    for (final hit in ranked) {
      final img = hit.imageUrl;
      if (img == null || img.isEmpty) continue;
      final vol = hit.parsed.volumeNumber;
      if (hit.parsed.hasSeries &&
          hit.parsed.seriesName != null &&
          BookTitleParser.seriesNamesMatch(hit.parsed.seriesName!, seriesName) &&
          vol != null &&
          (vol - volumeNumber).abs() < 0.01) {
        return img;
      }
    }

    for (final hit in ranked) {
      final img = hit.imageUrl;
      if (img != null && img.isNotEmpty) return img;
    }

    return OpenLibraryService.lookupVolumeCover(
      seriesName,
      volumeNumber,
      subcategory,
    );
  }

  static bool _matchesFilters(EnrichedBookHit hit, BookSearchFilters filters) {
    final authorQ = filters.authorQuery.trim().toLowerCase();
    if (authorQ.isNotEmpty) {
      final author = (hit.author ?? hit.raw['author'] ?? '').toLowerCase();
      if (!author.contains(authorQ)) return false;
    }
    final pubQ = filters.publisherQuery.trim().toLowerCase();
    if (pubQ.isNotEmpty) {
      final pub = (hit.publisher ?? hit.raw['publisher'] ?? '').toLowerCase();
      if (!pub.contains(pubQ)) return false;
    }
    final titleQ = filters.titleQuery.trim().toLowerCase();
    if (titleQ.isNotEmpty) {
      final title = hit.displayTitle.toLowerCase();
      final series = hit.parsed.seriesName?.toLowerCase() ?? '';
      if (!title.contains(titleQ) && !series.contains(titleQ)) return false;
    }
    return true;
  }

  static EnrichedBookHit _enrich(
    Map<String, String> hit,
    BookSubcategory subcategory,
  ) {
    final title = hit['title']?.trim() ?? '';
    final parsed = BookTitleParser.parse(title);
    final seriesFromMeta = hit['series_title']?.trim();
    final seriesName = parsed.seriesName ??
        (seriesFromMeta != null && seriesFromMeta.length >= 2
            ? seriesFromMeta
            : null);

    final normalizedParsed = ParsedBookTitle(
      rawTitle: title,
      seriesName: seriesName,
      volumeNumber: parsed.volumeNumber,
    );

    final author = hit['author']?.trim();
    final publisher = hit['publisher']?.trim();
    final volHint = _parseInt(hit['series_volume_count']) ??
        _parseInt(hit['volume_count']);
    final volFromNumber = normalizedParsed.volumeNumber?.ceil() ?? 0;
    var estimated = volHint;
    if (estimated == null || estimated < volFromNumber) {
      estimated = volFromNumber > 0 ? volFromNumber : null;
    }
    if (estimated != null && estimated > 300) estimated = null;

    final popularity = _popularityScore(hit);
    final seriesBonus = normalizedParsed.hasSeries ? 12.0 : 0.0;
    final coverBonus =
        (hit['image_url'] ?? '').isNotEmpty ? 4.0 : 0.0;
    final authorBonus = (author != null && author.isNotEmpty) ? 2.0 : 0.0;
    final canonicalBonus = _canonicalEditionBonus(title, author);

    return EnrichedBookHit(
      raw: hit,
      parsed: normalizedParsed,
      displayTitle: normalizedParsed.itemTitle,
      author: author,
      publisher: publisher,
      estimatedTotalVolumes: estimated,
      score: popularity + seriesBonus + coverBonus + authorBonus + canonicalBonus,
    );
  }

  /// Éditions majeures / récentes (ex. Dune — Frank Herbert).
  static double _canonicalEditionBonus(String title, String? author) {
    var bonus = 0.0;
    final t = title.toLowerCase();
    final a = author?.toLowerCase() ?? '';

    if (t == 'dune' || t.startsWith('dune ')) {
      bonus += 40;
      if (a.contains('herbert')) bonus += 30;
    }
    if (a.contains('tolkien') && t.contains('seigneur')) bonus += 25;
    if (a.contains('rowling') && t.contains('harry')) bonus += 25;
    if (a.contains('martin') && t.contains('game of thrones')) bonus += 20;

    final year = int.tryParse(
      RegExp(r'\b(19|20)\d{2}\b').firstMatch(title)?.group(0) ?? '',
    );
    if (year != null && year >= 2015) bonus += 3;
    if (year != null && year >= 2000 && year < 2015) bonus += 1;

    return bonus;
  }

  static double _popularityScore(Map<String, String> hit) {
    var score = 0.0;
    final ratings = _parseInt(hit['ratings_count']) ?? 0;
    score += ratings.clamp(0, 5000) / 500.0;
    final year = int.tryParse(hit['year'] ?? '');
    if (year != null) {
      if (year >= 2010) score += 2;
      if (year >= 1990) score += 1;
    }
    if ((hit['source'] ?? '') == 'google') score += 0.5;
    return score;
  }

  static double _queryMatchScore(EnrichedBookHit hit, String q) {
    final title = hit.displayTitle.toLowerCase();
    final series = hit.parsed.seriesName?.toLowerCase() ?? '';
    final author = (hit.author ?? '').toLowerCase();
    if (title == q || series == q) return 100;
    if (title.startsWith(q) || series.startsWith(q)) return 80;
    if (title.contains(q) || series.contains(q)) return 50;
    if (author.contains(q)) return 40;
    return 0;
  }

  static int? _parseInt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw.replaceAll(RegExp(r'[^\d]'), ''));
  }
}

class _SeriesAgg {
  String displayName;
  int maxVol = 0;
  final Map<int, String> covers = {};

  _SeriesAgg({required this.displayName});
}
