import '../models/book_subcategory.dart';
import '../utils/book_series_normalizer.dart';
import '../utils/book_title_parser.dart';
import '../utils/book_vf_edition.dart';
import 'google_books_service.dart';

/// Bannière série détectée dans les résultats de recherche.
class SeriesBannerCandidate {
  final String name;
  final int volumeCount;
  final Map<int, String> coversByVolume;
  /// Dates VF par tome (`published_date` ISO) — pour badge « À paraître ».
  final Map<int, String> publishedDatesByVolume;
  final BookSubcategory? detectedSubcategory;
  /// Auteur dominant détecté dynamiquement dans les hits API.
  final String? author;
  /// Couverture série (ex. AniList) si pas encore de tome 1.
  final String? coverUrl;
  /// Provenance AniList (bannière officielle manga).
  final bool fromAnilist;

  const SeriesBannerCandidate({
    required this.name,
    required this.volumeCount,
    this.coversByVolume = const {},
    this.publishedDatesByVolume = const {},
    this.detectedSubcategory,
    this.author,
    this.coverUrl,
    this.fromAnilist = false,
  });
}

/// Agrégat VF depuis la grille « Tomes reliés » (prioritaire sur MangaDex/AniList).
typedef VfSeriesCatalog = ({
  Map<int, String> covers,
  Map<int, String> dates,
  int maxVol,
});

VfSeriesCatalog vfCatalogFromHits(
  List<EnrichedBookHit> hits,
  String seriesName,
) {
  final want = BookSeriesNormalizer.mergeKey(seriesName);
  final covers = <int, String>{};
  final dates = <int, String>{};
  var maxVol = 0;
  for (final h in hits) {
    final sn = h.parsed.seriesName ?? h.raw['series_title'];
    if (sn == null || sn.isEmpty) continue;
    if (BookSeriesNormalizer.mergeKey(sn) != want) continue;
    final n = h.parsed.volumeNumber?.round();
    if (n == null || n < 1) continue;
    final title = h.raw['title'] ?? h.displayTitle;
    if (!BookVfEdition.isFrenchEdition(
      title: title,
      language: h.raw['language'],
      source: h.raw['source'],
    )) {
      continue;
    }
    if (n > maxVol) maxVol = n;
    final img = h.imageUrl;
    if (img != null && img.isNotEmpty) {
      final prev = covers[n];
      final prevMd = prev != null && prev.contains('mangadex');
      final curMd = img.contains('mangadex');
      // GB FR / iTunes FR écrasent MangaDex.
      if (prev == null || prev.isEmpty || (prevMd && !curMd)) {
        covers[n] = img;
      }
    }
    final pub = h.publishedDate;
    if (pub != null && pub.isNotEmpty) {
      dates[n] = pub;
    }
  }
  return (covers: covers, dates: dates, maxVol: maxVol);
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

  String? get publishedDate {
    final u = raw['published_date'];
    if (u == null || u.isEmpty) return null;
    return u;
  }

  /// « À paraître » uniquement si fiche VF (jamais US Vol. / MangaDex seul).
  bool get isUpcoming {
    final title = raw['title'] ?? displayTitle;
    if (!BookVfEdition.canShowUpcoming(
      title: title,
      language: raw['language'],
      source: raw['source'],
      publishedDate: publishedDate,
    )) {
      return false;
    }
    return BookIntelligenceService.isFuturePublishedDate(publishedDate);
  }

  /// Badge mauve daté : `⏳ À paraître · JJ/MM/AAAA`.
  String? get upcomingLabel {
    if (!isUpcoming) return null;
    final rawDate = publishedDate!;
    DateTime? d = DateTime.tryParse(rawDate);
    d ??= RegExp(r'^\d{4}-\d{2}$').hasMatch(rawDate)
        ? DateTime.tryParse('$rawDate-01')
        : null;
    if (d == null) return '⏳ À paraître';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '⏳ À paraître · $dd/$mm/${d.year}';
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

  /// Regroupe les hits par (série normalisée, sous-catégorie) — pas par auteur.
  /// Une bannière n'apparaît que s'il existe ≥1 tome numéroté réel (pas scan).
  static List<SeriesBannerCandidate> extractSeriesBanners(
    List<EnrichedBookHit> hits, {
    required String query,
    required BookSubcategory subcategory,
  }) {
    final groups = <String, _SeriesAgg>{};
    for (final h in hits) {
      final title = h.raw['title'] ?? h.displayTitle;
      if (BookSeriesNormalizer.looksLikeChapterOrScan(title)) continue;
      final rawName = (h.parsed.seriesName ?? '').trim();
      if (rawName.length < 2) continue;
      final name = BookSeriesNormalizer.displaySeriesName(rawName);
      if (name.length < 2) continue;
      final author = h.author?.trim();
      final det = h.detectedSubcategory ??
          BookSeriesNormalizer.detectSubcategory(
            seriesName: name,
            title: title,
            publisher: h.publisher,
            subjects: h.raw['subjects'] ?? h.raw['categories'],
          ) ??
          subcategory;
      final key = BookSeriesNormalizer.seriesSubcategoryKey(name, det);
      final agg = groups.putIfAbsent(
        key,
        () => _SeriesAgg(
          displayName: name,
          author: author,
          subcategory: det,
        ),
      );
      if (name.length < agg.displayName.length) agg.displayName = name;
      if (author != null && author.isNotEmpty) {
        final aKey = BookSeriesNormalizer.normalizeAuthorKey(author);
        agg.authorVotes[aKey] = (agg.authorVotes[aKey] ?? 0) + 1;
        agg.authorLabels.putIfAbsent(aKey, () => author);
        // Préfère l'auteur du tome 1 comme indicateur.
        final n = h.parsed.volumeNumber?.round();
        if (n == 1) agg.tome1Author = author;
      }
      final n = h.parsed.volumeNumber?.round();
      if (n != null && n > 0) {
        agg.numberedVolumes++;
        if (n > agg.maxVol) agg.maxVol = n;
        final img = h.imageUrl;
        if (img != null && img.isNotEmpty) {
          agg.covers.putIfAbsent(n, () => img);
        }
      }
    }

    final parsedQuery = BookSeriesNormalizer.parseCatalogSearchQuery(query);
    final bannerSeed = parsedQuery.seriesQuery.trim().isNotEmpty
        ? parsedQuery.seriesQuery.trim()
        : query.trim();

    final qKey = BookSeriesNormalizer.normalizeKey(bannerSeed);
    final banners = <SeriesBannerCandidate>[];
    for (final agg in groups.values) {
      if (agg.numberedVolumes < 1) continue;
      final count = agg.maxVol < 1 ? 1 : agg.maxVol;
      banners.add(
        SeriesBannerCandidate(
          name: agg.displayName,
          volumeCount: count,
          coversByVolume: Map<int, String>.from(agg.covers),
          detectedSubcategory: agg.subcategory,
          author: agg.tome1Author ?? agg.dominantAuthor,
          coverUrl: agg.covers[1],
        ),
      );
    }
    banners.sort((a, b) {
      final aq = BookSeriesNormalizer.normalizeKey(a.name).contains(qKey);
      final bq = BookSeriesNormalizer.normalizeKey(b.name).contains(qKey);
      if (aq != bq) return aq ? -1 : 1;
      return b.volumeCount.compareTo(a.volumeCount);
    });
    final relevant = banners.where((b) {
      final k = BookSeriesNormalizer.normalizeKey(b.name);
      return qKey.isEmpty ||
          k.contains(qKey) ||
          qKey.contains(k) ||
          k.split(' ').any((p) => p.length >= 4 && qKey.contains(p));
    }).toList();
    final use = relevant.isNotEmpty ? relevant : banners;
    return use.take(8).toList();
  }

  /// Batch unique Google Books (1–3 pages séquentielles) → map tome → cover.
  /// JAMAIS une requête par tome.
  static Future<Map<int, ({String coverUrl, String? publishedDate})>>
      batchFetchSeriesCovers({
    required String seriesName,
    required BookSubcategory subcategory,
    String? authorHint,
    int maxPages = 3,
  }) async {
    final cleanName = BookSeriesNormalizer.coverSearchSeriesName(seriesName);
    if (cleanName.length < 2) return {};

    var hits = await GoogleBooksService.searchSeriesBatched(
      cleanName,
      author: authorHint,
      maxPages: maxPages,
      langRestrict: 'fr',
    );
    if (hits.isEmpty) {
      hits = await GoogleBooksService.searchSeriesBatched(
        cleanName,
        author: authorHint,
        maxPages: 2,
        langRestrict: null,
      );
    }

    final ranked = enrichAndRank(
      hits,
      subcategory: subcategory,
      filters: BookSearchFilters(
        titleQuery: cleanName,
        authorQuery: authorHint ?? '',
      ),
    );

    final out = <int, ({String coverUrl, String? publishedDate})>{};
    final vfPrefer = <int, bool>{};
    for (final h in ranked) {
      final img = h.imageUrl;
      if (img == null || img.isEmpty) continue;
      final title = h.raw['title'] ?? h.displayTitle;
      if (BookSeriesNormalizer.looksLikeChapterOrScan(title)) continue;
      if (!BookSeriesNormalizer.hitBelongsToSeries(title, cleanName)) continue;
      final n = h.parsed.volumeNumber?.round();
      if (n == null || n < 1) continue;
      if (!hitMatchesVolumeExactly(h, n)) continue;
      final isVf = looksVfTitle(title);
      final pub = h.raw['published_date'] ?? h.raw['year'];
      if (!out.containsKey(n) || (isVf && vfPrefer[n] != true)) {
        out[n] = (coverUrl: img, publishedDate: pub);
        vfPrefer[n] = isVf;
      }
    }
    return out;
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

  /// Couverture d'UN tome via le batch série (1–3 requêtes), jamais 8+ appels.
  static Future<({String? coverUrl, String? publishedDate, bool upcoming})>
      lookupVolumeCoverMeta({
    required String seriesName,
    required double volumeNumber,
    required BookSubcategory subcategory,
    String? authorHint,
  }) async {
    final target = volumeNumber.round();
    final batch = await batchFetchSeriesCovers(
      seriesName: seriesName,
      subcategory: subcategory,
      authorHint: authorHint,
      maxPages: 2,
    );
    final hit = batch[target];
    if (hit == null) {
      return (coverUrl: null, publishedDate: null, upcoming: false);
    }
    return (
      coverUrl: hit.coverUrl,
      publishedDate: hit.publishedDate,
      upcoming: isFuturePublishedDate(hit.publishedDate),
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
    // Bonus léger pour éditions récentes (année dans le titre), sans auteurs hardcodés.
    var yearBonus = 0.0;
    final year = int.tryParse(
      RegExp(r'\b(19|20)\d{2}\b').firstMatch(title)?.group(0) ?? '',
    );
    if (year != null && year >= 2015) yearBonus = 3;
    if (year != null && year >= 2000 && year < 2015) yearBonus = 1;

    final source = (hit['source'] ?? hit['catalog_source'] ?? '')
        .toLowerCase()
        .trim();
    // MangaDex / AniList → toujours Manga (jamais « Autre »).
    final BookSubcategory? detected;
    if (source == 'mangadex' ||
        source == 'anilist' ||
        source.contains('mangadex') ||
        source.contains('anilist')) {
      detected = BookSubcategory.manga;
    } else {
      detected = BookSeriesNormalizer.detectSubcategory(
        seriesName: seriesName,
        title: title,
        publisher: publisher,
        subjects: hit['subjects'] ?? hit['categories'],
      );
    }

    return EnrichedBookHit(
      raw: hit,
      parsed: normalizedParsed,
      displayTitle: normalizedParsed.itemTitle,
      author: author,
      publisher: publisher,
      estimatedTotalVolumes: estimated,
      score: popularity + seriesBonus + coverBonus + authorBonus + yearBonus,
      detectedSubcategory: detected,
    );
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
  String? author;
  String? tome1Author;
  BookSubcategory? subcategory;
  int maxVol = 0;
  int numberedVolumes = 0;
  final Map<int, String> covers = {};
  final Map<String, int> authorVotes = {};
  final Map<String, String> authorLabels = {};

  _SeriesAgg({
    required this.displayName,
    this.author,
    this.subcategory,
  });

  String? get dominantAuthor {
    if (authorVotes.isEmpty) return author;
    var bestKey = authorVotes.keys.first;
    var bestVotes = authorVotes[bestKey] ?? 0;
    for (final e in authorVotes.entries) {
      if (e.value > bestVotes) {
        bestKey = e.key;
        bestVotes = e.value;
      }
    }
    return authorLabels[bestKey] ?? author;
  }
}
