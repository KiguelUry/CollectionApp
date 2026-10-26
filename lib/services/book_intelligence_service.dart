import '../models/book_subcategory.dart';
import '../utils/book_series_normalizer.dart';
import '../utils/book_title_parser.dart';
import 'google_books_service.dart';
import 'itunes_books_service.dart';
import 'open_library_service.dart';

/// Bannière série détectée dans les résultats de recherche.
class SeriesBannerCandidate {
  final String name;
  final int volumeCount;
  final Map<int, String> coversByVolume;
  final BookSubcategory? detectedSubcategory;

  const SeriesBannerCandidate({
    required this.name,
    required this.volumeCount,
    this.coversByVolume = const {},
    this.detectedSubcategory,
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
  /// Catégorie déduite (éditeur / série), indépendante de la pilule UI.
  final BookSubcategory? detectedSubcategory;

  const EnrichedBookHit({
    required this.raw,
    required this.parsed,
    required this.displayTitle,
    this.author,
    this.publisher,
    this.estimatedTotalVolumes,
    required this.score,
    this.detectedSubcategory,
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

  static final _vfCompactTitle = RegExp(
    r'\bt\.?\s*\d+\b',
    caseSensitive: false,
  );

  static bool looksVfTitle(String title) {
    final t = title.toLowerCase();
    return t.contains('tome') || _vfCompactTitle.hasMatch(t);
  }

  static bool looksEnVolTitle(String title) {
    final t = title.toLowerCase();
    return t.contains('vol.') ||
        t.contains('volume ') ||
        RegExp(r',\s*vol\.?\s*\d', caseSensitive: false).hasMatch(t);
  }

  static bool _preferHit(EnrichedBookHit a, EnrichedBookHit b) {
    final aCover = a.imageUrl != null && a.imageUrl!.isNotEmpty;
    final bCover = b.imageUrl != null && b.imageUrl!.isNotEmpty;
    if (aCover != bCover) return aCover;
    final aTitle = a.displayTitle.toLowerCase();
    final bTitle = b.displayTitle.toLowerCase();
    final aVf = looksVfTitle(aTitle);
    final bVf = looksVfTitle(bTitle);
    final aEn = looksEnVolTitle(aTitle);
    final bEn = looksEnVolTitle(bTitle);
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
      final rawName = (h.parsed.seriesName ?? '').trim();
      if (rawName.length < 2) continue;
      // AVANT regroupement : « Kingdom - Tome » → « Kingdom » (1 seule bannière).
      final name = BookSeriesNormalizer.displaySeriesName(rawName);
      if (name.length < 2) continue;
      final key = BookSeriesNormalizer.mergeKey(name);
      final agg = groups.putIfAbsent(
        key,
        () => _SeriesAgg(displayName: name),
      );
      // Préfère le nom le plus court / propre (« Kingdom » > « Kingdom - Tome »).
      if (name.length < agg.displayName.length) agg.displayName = name;
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
    // « kingdom 1 » → série « Kingdom » (pas « kingdom 1 »).
    final parsedQuery = BookSeriesNormalizer.parseCatalogSearchQuery(query);
    final bannerSeed = parsedQuery.seriesQuery.trim().isNotEmpty
        ? parsedQuery.seriesQuery.trim()
        : query.trim();
    if (groups.isEmpty && bannerSeed.length >= 2) {
      final dict = BookSeriesNormalizer.expectedCount(bannerSeed, subcategory);
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
            name: BookSeriesNormalizer.displaySeriesName(bannerSeed),
            volumeCount: count > 0 ? count : (dict ?? 1),
          ),
        ];
      }
      return const [];
    }

    final qKey = BookSeriesNormalizer.normalizeKey(bannerSeed);
    final banners = <SeriesBannerCandidate>[];
    for (final agg in groups.values) {
      final dict = BookSeriesNormalizer.expectedCount(
            agg.displayName,
            subcategory,
          ) ??
          0;
      final count = [agg.maxVol, dict].reduce((a, b) => a > b ? a : b);
      if (count < 1 && agg.covers.isEmpty) continue;
      final detected = BookSeriesNormalizer.detectSubcategory(
        seriesName: agg.displayName,
      );
      banners.add(
        SeriesBannerCandidate(
          name: agg.displayName,
          volumeCount: count < 1 ? 1 : count,
          coversByVolume: Map<int, String>.from(agg.covers),
          detectedSubcategory: detected,
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
    final name = BookSeriesNormalizer.coverSearchSeriesName(seriesName);
    final vol = volumeNumber == volumeNumber.roundToDouble()
        ? volumeNumber.toInt().toString()
        : volumeNumber.toString();
    return '$name Tome $vol';
  }

  /// Variante VF compacte Fnac/Kana : « Kagurabachi T10 ».
  static String volumeSearchQueryCompact(
    String seriesName,
    double volumeNumber,
  ) {
    final name = BookSeriesNormalizer.coverSearchSeriesName(seriesName);
    final vol = volumeNumber == volumeNumber.roundToDouble()
        ? volumeNumber.toInt().toString()
        : volumeNumber.toString();
    return '$name T$vol';
  }

  /// Variante Glénat avec zéro : « One Piece T01 » / « Tome 01 ».
  static String volumeSearchQueryPadded(
    String seriesName,
    double volumeNumber,
  ) {
    final name = BookSeriesNormalizer.coverSearchSeriesName(seriesName);
    final n = volumeNumber.round();
    final padded = n.toString().padLeft(2, '0');
    return '$name T$padded';
  }

  /// Hit catalogue dont le n° de tome matche [target] de façon stricte.
  static bool hitMatchesVolumeExactly(EnrichedBookHit hit, int target) {
    final title = hit.raw['title'] ?? hit.displayTitle;
    final subtitle = hit.raw['subtitle'] ?? '';
    final combined = '$title $subtitle';
    return BookTitleParser.titleMatchesVolumeExactly(combined, target);
  }

  /// Couverture + méta (date) pour un tome — match STRICT n° + série (+ auteur).
  static Future<({String? coverUrl, String? publishedDate, bool upcoming})>
      lookupVolumeCoverMeta({
    required String seriesName,
    required double volumeNumber,
    required BookSubcategory subcategory,
    String? authorHint,
  }) async {
    final target = volumeNumber.round();
    final cleanName = BookSeriesNormalizer.coverSearchSeriesName(seriesName);
    final authors = BookSeriesNormalizer.knownAuthorsFor(cleanName);
    final authorQ = authorHint?.trim().isNotEmpty == true
        ? authorHint!.trim()
        : (authors != null && authors.isNotEmpty ? authors.first : null);

    var query = volumeSearchQuery(cleanName, volumeNumber);
    if (authorQ != null) query = '$query $authorQ';
    if (query.trim().length < 3) {
      return (coverUrl: null, publishedDate: null, upcoming: false);
    }

    final compact = volumeSearchQueryCompact(cleanName, volumeNumber);
    final padded = volumeSearchQueryPadded(cleanName, volumeNumber);
    final merged = <Map<String, String>>[];
    final seen = <String>{};
    for (final list in [
      await GoogleBooksService.search(query, maxResults: 16, langRestrict: 'fr'),
      await GoogleBooksService.search(
        compact,
        maxResults: 12,
        langRestrict: 'fr',
      ),
      if (padded != compact)
        await GoogleBooksService.search(
          padded,
          maxResults: 10,
          langRestrict: 'fr',
        ),
      await ItunesBooksService.search(query),
      await ItunesBooksService.search(compact),
      if (padded != compact) await ItunesBooksService.search(padded),
      await GoogleBooksService.search(query, maxResults: 16),
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
      filters: BookSearchFilters(titleQuery: cleanName),
    );

    EnrichedBookHit? best;
    for (final hit in ranked) {
      final img = hit.imageUrl;
      if (img == null || img.isEmpty) continue;
      if (!hitMatchesVolumeExactly(hit, target)) continue;
      final title = hit.raw['title'] ?? hit.displayTitle;
      if (!BookSeriesNormalizer.hitBelongsToSeries(title, cleanName)) {
        continue;
      }
      if (!BookSeriesNormalizer.authorMatchesSeries(hit.author, cleanName)) {
        continue;
      }
      if (best == null || _preferHit(hit, best)) best = hit;
    }

    if (best == null) {
      return (coverUrl: null, publishedDate: null, upcoming: false);
    }

    final pub = best.raw['published_date'] ?? best.raw['year'];
    final upcoming = isFuturePublishedDate(pub);
    return (
      coverUrl: best.imageUrl,
      publishedDate: pub,
      upcoming: upcoming,
    );
  }

  static bool isFuturePublishedDate(String? raw) {
    if (raw == null || raw.isEmpty) return false;
    DateTime? d = DateTime.tryParse(raw);
    d ??= RegExp(r'^\d{4}-\d{2}$').hasMatch(raw)
        ? DateTime.tryParse('$raw-01')
        : null;
    d ??= RegExp(r'^\d{4}$').hasMatch(raw)
        ? DateTime.tryParse('$raw-01-01')
        : null;
    if (d == null) return false;
    final today = DateTime.now();
    return d.isAfter(DateTime(today.year, today.month, today.day));
  }

  /// Couverture d'un tome via Google Books + iTunes (+ OL).
  /// Match STRICT du numéro — jamais de couverture d'un autre tome.
  static Future<String?> lookupVolumeCover({
    required String seriesName,
    required double volumeNumber,
    required BookSubcategory subcategory,
  }) async {
    final meta = await lookupVolumeCoverMeta(
      seriesName: seriesName,
      volumeNumber: volumeNumber,
      subcategory: subcategory,
    );
    return meta.coverUrl;
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

    final detected = BookSeriesNormalizer.detectSubcategory(
      seriesName: seriesName,
      title: title,
      publisher: publisher,
      subjects: hit['subjects'] ?? hit['categories'],
    );

    // Prefer dictionnaire série pour le total (Kingdom → 73, pas tome 2).
    if (seriesName != null) {
      final dict = BookSeriesNormalizer.expectedCount(
        seriesName,
        detected ?? subcategory,
      );
      if (dict != null && (estimated == null || estimated < dict)) {
        estimated = dict;
      }
    }

    return EnrichedBookHit(
      raw: hit,
      parsed: normalizedParsed,
      displayTitle: normalizedParsed.itemTitle,
      author: author,
      publisher: publisher,
      estimatedTotalVolumes: estimated,
      score: popularity + seriesBonus + coverBonus + authorBonus + canonicalBonus,
      detectedSubcategory: detected,
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
