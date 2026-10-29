import '../models/book_subcategory.dart';
import '../utils/book_series_normalizer.dart';
import '../utils/book_title_parser.dart';
import '../utils/book_vf_edition.dart';
import 'google_books_service.dart';
import 'itunes_books_service.dart';

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
  final ownedHits = <EnrichedBookHit>[];
  for (final h in hits) {
    final sn = h.parsed.seriesName ?? h.raw['series_title'];
    if (sn == null || sn.isEmpty) continue;
    if (BookSeriesNormalizer.mergeKey(sn) != want) continue;
    final n = h.parsed.volumeNumber?.round();
    if (n == null || n < 1) continue;
    final src = (h.raw['source'] ?? '').toLowerCase();
    if (src.contains('mangadex')) continue;
    ownedHits.add(h);
  }
  final anyCollected = ownedHits.any(
    (h) => BookTitleParser.looksLikeCollectedTome(
      h.raw['title'] ?? h.displayTitle,
    ),
  );
  for (final h in ownedHits) {
    final n = h.parsed.volumeNumber!.round();
    final title = h.raw['title'] ?? h.displayTitle;
    if (anyCollected && !BookTitleParser.looksLikeCollectedTome(title)) {
      continue;
    }
    if (BookTitleParser.looksLikeUsIssue(title) &&
        !BookTitleParser.looksLikeCollectedTome(title)) {
      continue;
    }
    if (BookTitleParser.looksLikeIntegraleEdition(title) &&
        !BookTitleParser.looksLikeIntegraleEdition(seriesName)) {
      continue;
    }
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
    final rawDate = publishedDate;
    if (rawDate == null || rawDate.isEmpty) return '⏳ À paraître';
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
    var enriched = hits
        .map(
          (hit) => _enrich(
            hit,
            subcategory,
            queryHint: filters.titleQuery,
          ),
        )
        .toList();
    enriched = inferSharedPrefixSeries(enriched, queryHint: filters.titleQuery);
    // Jamais sur Manga / BD / Comics : le n° de tome du titre fait foi.
    if (subcategory == BookSubcategory.novel ||
        subcategory == BookSubcategory.other) {
      enriched = assignPublicationOrderVolumes(
        enriched,
        queryHint: filters.titleQuery,
      );
    }

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

    List<EnrichedBookHit> onlyIdentity(List<EnrichedBookHit> list) {
      final q = filters.titleQuery.trim();
      if (q.length < 3) return list;
      return list
          .where(
            (h) => BookSeriesNormalizer.queryWordsMatchIdentity(
              query: q,
              title: h.raw['title'] ?? h.displayTitle,
              subtitle: h.raw['subtitle'],
              collectionName: h.raw['collection_name'],
              seriesTitle: h.raw['series_title'] ?? h.parsed.seriesName,
            ),
          )
          .toList();
    }

    final deduped = onlyIdentity(dedupeBySeriesVolume(filtered));
    if (deduped.isEmpty && enriched.isNotEmpty) {
      return sortByVolumeThenScore(
        onlyIdentity(dedupeBySeriesVolume(enriched)),
      );
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
      final vol = h.parsed.volumeNumber?.round();
      final titleKey = BookSeriesNormalizer.normalizeKey(
        h.raw['title'] ?? h.displayTitle,
      );
      final key = vol == null ? '$seriesKey|unit|$titleKey' : '$seriesKey|$vol';
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
            author: author,
            comicsContent: h.raw['comics_content'] == 'true',
          ) ??
          subcategory;
      // Homonymes : Monster Urasawa ≠ Monster Brittany Adams.
      final authorPart = author != null && author.isNotEmpty
          ? '|${BookSeriesNormalizer.normalizeAuthorKey(author)}'
          : '';
      final key =
          '${BookSeriesNormalizer.seriesSubcategoryKey(name, det)}$authorPart';
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
      final ak = BookSeriesNormalizer.normalizeKey(a.name);
      final bk = BookSeriesNormalizer.normalizeKey(b.name);
      // Exact match query → toujours 1er (Berserk > Berserk de la Gourmandise).
      final aExact = qKey.isNotEmpty && ak == qKey;
      final bExact = qKey.isNotEmpty && bk == qKey;
      if (aExact != bExact) return aExact ? -1 : 1;
      final aStarts = qKey.isNotEmpty && ak.startsWith(qKey);
      final bStarts = qKey.isNotEmpty && bk.startsWith(qKey);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      final aq = ak.contains(qKey);
      final bq = bk.contains(qKey);
      if (aq != bq) return aq ? -1 : 1;
      // Titre plus court = plus exact (Berserk avant Berserk de la Gourmandise).
      if (ak.length != bk.length && (aq || bq)) {
        return ak.length.compareTo(bk.length);
      }
      return b.volumeCount.compareTo(a.volumeCount);
    });
    final relevant = banners.where((b) {
      final k = BookSeriesNormalizer.normalizeKey(b.name);
      return qKey.isEmpty ||
          k == qKey ||
          k.contains(qKey) ||
          qKey.contains(k) ||
          k.split(' ').any((p) => p.length >= 4 && qKey.contains(p));
    }).toList();
    final use = relevant.isNotEmpty ? relevant : banners;
    return use.take(8).toList();
  }

  /// Force Manga sur tout hit dont la série est confirmée AniList/MangaDex.
  static List<EnrichedBookHit> forceMangaForOfficialSeries(
    List<EnrichedBookHit> hits,
    Set<String> officialMergeKeys,
  ) {
    if (officialMergeKeys.isEmpty) return hits;
    return hits.map((h) {
      final sn = h.parsed.seriesName ?? h.raw['series_title'] ?? h.displayTitle;
      final key = BookSeriesNormalizer.mergeKey(sn);
      if (!officialMergeKeys.contains(key)) return h;
      if (h.detectedSubcategory == BookSubcategory.manga) return h;
      final locked = BookSeriesNormalizer.detectSubcategory(
        seriesName: sn,
        title: h.displayTitle,
        publisher: h.publisher,
        author: h.author,
        subjects: h.raw['categories'] ?? h.raw['subjects'],
      );
      if (locked == BookSubcategory.bd) return h;
      return EnrichedBookHit(
        raw: h.raw,
        parsed: h.parsed,
        displayTitle: h.displayTitle,
        author: h.author,
        publisher: h.publisher,
        estimatedTotalVolumes: h.estimatedTotalVolumes,
        score: h.score,
        detectedSubcategory: BookSubcategory.manga,
      );
    }).toList();
  }

  /// Score de pertinence série exacte pour tri grille (0 = exact).
  static int exactSeriesRank(EnrichedBookHit h, String queryKey) {
    if (queryKey.isEmpty) return 1;
    final sn = BookSeriesNormalizer.normalizeKey(
      h.parsed.seriesName ?? h.displayTitle,
    );
    if (sn == queryKey) return 0;
    if (sn.startsWith(queryKey)) return 1;
    if (sn.contains(queryKey)) return 2;
    return 3;
  }

  /// Batch unique Google Books (1–3 pages séquentielles) → map tome → cover.
  /// JAMAIS une requête par tome. [maxPages] jusqu'à 3 (= 120 items).
  static Future<
      Map<int, ({String coverUrl, String? publishedDate, String? language})>>
      batchFetchSeriesCovers({
    required String seriesName,
    required BookSubcategory subcategory,
    String? authorHint,
    int maxPages = 3,
  }) async {
    final cleanName = BookSeriesNormalizer.coverSearchSeriesName(seriesName);
    if (cleanName.length < 2 || maxPages < 1) return {};

    final hits = <Map<String, String>>[];
    final seenTitles = <String>{};
    void addHits(List<Map<String, String>> list) {
      for (final h in list) {
        final t = (h['title'] ?? '').toLowerCase();
        if (t.isEmpty || seenTitles.contains(t)) continue;
        seenTitles.add(t);
        hits.add(h);
      }
    }

    // Apple Books FR en premier (mangas inclus). Google Books ne comble que les trous.
    try {
      addHits(await ItunesBooksService.searchSeries(
        cleanName,
        author: authorHint,
        mangaPublisherPass: subcategory == BookSubcategory.manga,
      ));
    } catch (_) {}

    if (!GoogleBooksService.isCircuitOpen) {
      try {
        addHits(await GoogleBooksService.searchSeriesBatched(
          cleanName,
          author: authorHint,
          maxPages: 1,
          langRestrict: 'fr',
        ));
      } catch (_) {}
    }

    if ((authorHint ?? '').trim().length >= 2 &&
        (subcategory == BookSubcategory.novel ||
            subcategory == BookSubcategory.manga ||
            subcategory == BookSubcategory.bd ||
            subcategory == BookSubcategory.comics)) {
      try {
        final author = authorHint!.trim();
        final extraIt = await ItunesBooksService.search(
          '$cleanName $author',
          limit: 200,
        );
        for (final h in extraIt) {
          final t = (h['title'] ?? '').toLowerCase();
          if (t.isEmpty || seenTitles.contains(t)) continue;
          seenTitles.add(t);
          hits.add(h);
        }
      } catch (_) {}
    }

    final ranked = enrichAndRank(
      hits,
      subcategory: subcategory,
      filters: BookSearchFilters(
        titleQuery: cleanName,
        authorQuery: authorHint ?? '',
      ),
    );

    final out = <int, ({String coverUrl, String? publishedDate, String? language})>{};
    final vfPrefer = <int, bool>{};
    for (final h in ranked) {
      final img = h.imageUrl;
      if (img == null || img.isEmpty) continue;
      final title = h.raw['title'] ?? h.displayTitle;
      if (BookVfEdition.isRejectedCatalogTitle(
        title,
        subtitle: h.raw['subtitle'],
        author: h.author,
        publisher: h.publisher,
      )) {
        continue;
      }
      if (BookSeriesNormalizer.looksLikeChapterOrScan(title)) continue;
      final identity = BookSeriesNormalizer.catalogIdentityMatchesSeries(
        title: title,
        subtitle: h.raw['subtitle'],
        collectionName: h.raw['collection_name'],
        seriesTitle: h.raw['series_title'],
        seriesName: cleanName,
      );
      final descBind = BookSeriesNormalizer.descriptionBindsToSeries(
        author: h.author,
        expectedAuthor: authorHint,
        title: title,
        description: h.raw['description'] ?? '',
        seriesName: cleanName,
      );
      if (!identity && !descBind) continue;
      if (!BookSeriesNormalizer.authorMatchesExpected(h.author, authorHint)) {
        continue;
      }
      final n = h.parsed.volumeNumber?.round() ??
          (descBind
              ? BookTitleParser.extractVolumeFromProse(
                  h.raw['description'] ?? '',
                )
              : null);
      if (n == null || n < 1) continue;
      if (!hitMatchesVolumeExactly(h, n, seriesName: cleanName)) continue;
      final isVf = looksVfTitle(title) ||
          BookVfEdition.isFrenchLanguage(h.raw['language']);
      final isEn = BookVfEdition.isExplicitEnglish(h.raw['language']);
      final pub = h.raw['published_date'] ?? h.raw['year'];
      if (out.containsKey(n) && vfPrefer[n] == true && isEn && !isVf) {
        continue;
      }
      if (!out.containsKey(n) || (isVf && vfPrefer[n] != true)) {
        out[n] = (
          coverUrl: img,
          publishedDate: pub,
          language: h.raw['language'],
        );
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
  static bool hitMatchesVolumeExactly(
    EnrichedBookHit hit,
    int target, {
    String? seriesName,
  }) {
    final title = hit.raw['title'] ?? hit.displayTitle;
    final subtitle = hit.raw['subtitle'] ?? '';
    final combined = '$title $subtitle';
    if (BookTitleParser.titleMatchesVolumeExactly(combined, target)) {
      return true;
    }
    final landmark = BookTitleParser.volumeFromLandmark(
      '$combined ${hit.raw['description'] ?? ''}',
    );
    if (landmark == target) return true;
    final prose = BookTitleParser.extractVolumeFromProse(
      '${hit.raw['description'] ?? ''} $subtitle ${hit.raw['collection_name'] ?? ''}',
    );
    if (prose == target) return true;
    final series = seriesName ?? hit.parsed.seriesName ?? '';
    if (series.isNotEmpty &&
        BookTitleParser.volumeTrailingSeries(title, series) == target) {
      return true;
    }
    final api = int.tryParse(hit.raw['series_volume'] ?? '');
    return api == target;
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
    final cutoff = DateTime(today.year, today.month, today.day)
        .add(const Duration(days: 2));
    return d.isAfter(cutoff);
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
    BookSubcategory subcategory, {
    String? queryHint,
  }) {
    final title = hit['title']?.trim() ?? '';
    final subtitle = hit['subtitle']?.trim();
    final apiVol = int.tryParse(hit['series_volume'] ?? '');
    final parsed = BookTitleParser.parse(
      [title, if (subtitle != null && subtitle.isNotEmpty) subtitle]
          .join(' : '),
      apiVolumeNumber: apiVol,
      queryHint: queryHint,
    );
    final seriesFromMeta = hit['series_title']?.trim();
    var seriesName = parsed.seriesName ??
        (seriesFromMeta != null && seriesFromMeta.length >= 2
            ? seriesFromMeta
            : null);
    // collectionName Apple prime sur un découpage « Titre à … » du tome.
    if (queryHint != null &&
        queryHint.trim().length >= 3 &&
        seriesFromMeta != null &&
        seriesFromMeta.length >= 2 &&
        (BookSeriesNormalizer.namesMatch(seriesFromMeta, queryHint) ||
            BookSeriesNormalizer.textMentionsSeries(
              seriesFromMeta,
              queryHint,
            ))) {
      seriesName = BookSeriesNormalizer.displaySeriesName(seriesFromMeta);
    }
    final identityMatchesQuery = queryHint != null &&
        queryHint.trim().length >= 3 &&
        BookSeriesNormalizer.catalogIdentityMatchesSeries(
          title: title,
          subtitle: subtitle,
          collectionName: hit['collection_name'],
          seriesTitle: seriesFromMeta,
          seriesName: queryHint,
        );
    // Jamais la description pour décider de l'appartenance à la série.
    if ((seriesName == null || seriesName.isEmpty) && identityMatchesQuery) {
      seriesName = queryHint.trim();
    }
    final identified = parsed.seriesName != null ||
        (seriesFromMeta != null && seriesFromMeta.length >= 2) ||
        identityMatchesQuery;
    final proseBlob = identified
        ? '${hit['description'] ?? ''} ${hit['collection_name'] ?? ''} '
            '${hit['subtitle'] ?? ''} ${hit['series_title'] ?? ''}'
        : '${hit['collection_name'] ?? ''} ${hit['subtitle'] ?? ''} '
            '${hit['series_title'] ?? ''}';
    final proseVol = BookTitleParser.extractVolumeFromProse(proseBlob);
    final landmark = BookTitleParser.volumeFromLandmark(
      '$title ${subtitle ?? ''} ${hit['description'] ?? ''}',
    );
    final trailing = seriesName == null
        ? null
        : BookTitleParser.volumeTrailingSeries(title, seriesName);

    final normalizedParsed = ParsedBookTitle(
      rawTitle: title,
      seriesName: seriesName,
      volumeNumber: parsed.volumeNumber ??
          landmark?.toDouble() ??
          proseVol?.toDouble() ??
          trailing?.toDouble() ??
          (apiVol != null && apiVol >= 1 && apiVol < 1900
              ? apiVol.toDouble()
              : null),
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
        subjects: hit['subjects'] ?? hit['categories'] ?? hit['genre'],
        author: author,
        comicsContent: hit['comics_content'] == 'true',
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

  /// Si ≥3 livres du même auteur partagent un préfixe de titre,
  /// rattache-les à ce nom de série.
  static List<EnrichedBookHit> inferSharedPrefixSeries(
    List<EnrichedBookHit> hits, {
    String? queryHint,
  }) {
    if (hits.length < 3) return hits;
    final byAuthor = <String, List<int>>{};
    for (var i = 0; i < hits.length; i++) {
      final a = BookSeriesNormalizer.normalizeAuthorKey(hits[i].author ?? '');
      if (a.isEmpty) continue;
      if (BookTitleParser.isCompanionOrStudyTitle(
        hits[i].raw['title'] ?? hits[i].displayTitle,
      )) {
        continue;
      }
      byAuthor.putIfAbsent(a, () => []).add(i);
    }
    final out = List<EnrichedBookHit>.from(hits);
    for (final idxs in byAuthor.values) {
      if (idxs.length < 3) continue;
      final prefixes = <String, int>{};
      for (final i in idxs) {
        final title = out[i].raw['title'] ?? out[i].displayTitle;
        final inferred = BookTitleParser.inferSeriesName(
              title,
              queryHint: queryHint,
            ) ??
            _twoWordPrefix(title);
        if (inferred == null) continue;
        final k = BookSeriesNormalizer.normalizeKey(inferred);
        prefixes[k] = (prefixes[k] ?? 0) + 1;
      }
      String? best;
      var bestN = 0;
      prefixes.forEach((k, n) {
        if (n > bestN) {
          best = k;
          bestN = n;
        }
      });
      if (best == null || bestN < 3) continue;
      for (final i in idxs) {
        final h = out[i];
        if (h.parsed.hasSeries) continue;
        final title = h.raw['title'] ?? h.displayTitle;
        final inferred = BookTitleParser.inferSeriesName(
              title,
              queryHint: queryHint,
            ) ??
            _twoWordPrefix(title);
        if (inferred == null) continue;
        if (BookSeriesNormalizer.normalizeKey(inferred) != best) continue;
        final apiVol = _parseInt(h.raw['series_volume']);
        out[i] = EnrichedBookHit(
          raw: h.raw,
          parsed: ParsedBookTitle(
            rawTitle: h.parsed.rawTitle,
            seriesName: inferred,
            volumeNumber: h.parsed.volumeNumber ?? apiVol?.toDouble(),
          ),
          displayTitle: h.parsed.hasVolume || apiVol != null
              ? '$inferred - Tome ${h.parsed.volumeNumber?.round() ?? apiVol}'
              : h.displayTitle,
          author: h.author,
          publisher: h.publisher,
          estimatedTotalVolumes: h.estimatedTotalVolumes,
          score: h.score + 20,
          detectedSubcategory: h.detectedSubcategory,
        );
      }
    }
    return out;
  }

  /// Romans d’une saga (préfixe + à/et) : n° = ordre de publication.
  /// Ne touche jamais un Manga / BD / Comics, ni un livre qui a déjà `Tome N`.
  static List<EnrichedBookHit> assignPublicationOrderVolumes(
    List<EnrichedBookHit> hits, {
    String? queryHint,
  }) {
    if (hits.length < 2) return hits;
    final serial = hits.any((h) {
      final sub = h.detectedSubcategory;
      return sub == BookSubcategory.manga ||
          sub == BookSubcategory.bd ||
          sub == BookSubcategory.comics;
    });
    if (serial) return hits;
    final anyExplicit = hits.any((h) {
      final title = h.raw['title'] ?? h.displayTitle;
      if (BookTitleParser.extractVolumeNumberStrict(title) != null) {
        return true;
      }
      if (h.parsed.volumeNumber != null) return true;
      final prose = BookTitleParser.extractVolumeFromProse(
        '${h.raw['description'] ?? ''} ${h.raw['subtitle'] ?? ''} '
        '${h.raw['collection_name'] ?? ''}',
      );
      return prose != null;
    });
    if (anyExplicit) return hits;
    final groups = <String, List<int>>{};
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      final title = h.raw['title'] ?? h.displayTitle;
      if (BookTitleParser.isCompanionOrStudyTitle(title)) continue;
      if (BookVfEdition.isRejectedCatalogTitle(
        title,
        subtitle: h.raw['subtitle'],
      )) {
        continue;
      }
      final series = h.parsed.seriesName ??
          BookTitleParser.inferSeriesName(title, queryHint: queryHint);
      if (series == null || series.trim().length < 3) continue;
      if (!BookTitleParser.titleContinuesSeriesPrefix(title, series)) continue;
      final authorKey = BookSeriesNormalizer.normalizeAuthorKey(h.author ?? '');
      if (authorKey.isEmpty) continue;
      final key = '${BookSeriesNormalizer.mergeKey(series)}|$authorKey';
      groups.putIfAbsent(key, () => []).add(i);
    }
    final out = List<EnrichedBookHit>.from(hits);
    for (final idxs in groups.values) {
      if (idxs.length < 2) continue;
      idxs.sort((a, b) {
        final da = out[a].publishedDate ?? out[a].raw['year'] ?? '';
        final db = out[b].publishedDate ?? out[b].raw['year'] ?? '';
        return da.compareTo(db);
      });
      final dates = idxs
          .map((i) => out[i].publishedDate ?? out[i].raw['year'] ?? '')
          .where((d) => d.isNotEmpty)
          .toSet();
      if (dates.length != idxs.length) continue;
      String? seriesName;
      for (final i in idxs) {
        seriesName = out[i].parsed.seriesName ?? seriesName;
      }
      if (seriesName == null) continue;
      for (var n = 0; n < idxs.length; n++) {
        final i = idxs[n];
        final h = out[i];
        final vol = (n + 1).toDouble();
        if (h.parsed.volumeNumber?.round() == n + 1) continue;
        final raw = Map<String, String>.from(h.raw);
        raw['series_volume'] = '${n + 1}';
        raw['series_title'] = seriesName;
        out[i] = EnrichedBookHit(
          raw: raw,
          parsed: ParsedBookTitle(
            rawTitle: h.parsed.rawTitle,
            seriesName: seriesName,
            volumeNumber: vol,
          ),
          displayTitle: '$seriesName - Tome ${n + 1}',
          author: h.author,
          publisher: h.publisher,
          estimatedTotalVolumes: idxs.length,
          score: h.score + 30,
          detectedSubcategory: h.detectedSubcategory,
        );
      }
    }
    return out;
  }

  static String? _twoWordPrefix(String title) {
    final words = title.trim().split(RegExp(r'\s+'));
    if (words.length < 4) return null;
    return '${words[0]} ${words[1]}';
  }

  /// Étendue VF : max tome déjà paru en VF + premier « À paraître » VF.
  static ({int maxVf, int? firstUpcomingVf}) vfExtentFromHits(
    List<EnrichedBookHit> hits,
    String seriesName,
  ) {
    final want = BookSeriesNormalizer.mergeKey(seriesName);
    var maxVf = 0;
    int? firstUpcoming;
    for (final h in hits) {
      final sn = h.parsed.seriesName ?? h.raw['series_title'] ?? '';
      if (BookSeriesNormalizer.mergeKey(sn.isEmpty ? h.displayTitle : sn) !=
          want) {
        continue;
      }
      final n = h.parsed.volumeNumber?.round();
      if (n == null || n < 1) continue;
      final src = (h.raw['source'] ?? '').toLowerCase();
      final fromMd = src.contains('mangadex');
      if (fromMd) continue;
      if (h.isUpcoming) {
        if (firstUpcoming == null || n < firstUpcoming) firstUpcoming = n;
        if (n > maxVf) maxVf = n;
        continue;
      }
      if (n > maxVf) maxVf = n;
    }
    return (maxVf: maxVf, firstUpcomingVf: firstUpcoming);
  }

  /// Tome pas encore paru en France.
  static bool hitIsJapanReleaseOnly(
    EnrichedBookHit hit, {
    required int maxVf,
    int? firstUpcomingVf,
  }) {
    final n = hit.parsed.volumeNumber?.round();
    if (n == null) return false;
    if (firstUpcomingVf != null && n > firstUpcomingVf) return true;
    return maxVf > 0 && n > maxVf;
  }

  /// Déjà paru en VF, mais la couverture affichée est encore MangaDex.
  static bool hitShowsVoCover(
    EnrichedBookHit hit, {
    required int maxVf,
    int? firstUpcomingVf,
  }) {
    if (hitIsJapanReleaseOnly(
      hit,
      maxVf: maxVf,
      firstUpcomingVf: firstUpcomingVf,
    )) {
      return false;
    }
    final src = (hit.raw['source'] ?? '').toLowerCase();
    final img = hit.imageUrl ?? '';
    return src.contains('mangadex') || img.contains('mangadex');
  }

  static bool hitIsJapaneseVo(
    EnrichedBookHit hit, {
    required int maxVf,
    int? firstUpcomingVf,
  }) {
    final src = (hit.raw['source'] ?? '').toLowerCase();
    if (!src.contains('mangadex')) return false;
    final n = hit.parsed.volumeNumber?.round();
    if (n == null) return false;
    if (firstUpcomingVf != null && n > firstUpcomingVf) return true;
    return n > maxVf;
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
