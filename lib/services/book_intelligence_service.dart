import '../models/book_subcategory.dart';
import '../utils/book_title_parser.dart';
import 'google_books_service.dart';
import 'open_library_service.dart';

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

    return filtered;
  }

  static EnrichedBookHit enrichSingle(
    Map<String, String> hit,
    BookSubcategory subcategory,
  ) =>
      _enrich(hit, subcategory);

  /// Requête catalogue pour un tome (ex. « Thorgal 1 »).
  static String volumeSearchQuery(String seriesName, double volumeNumber) {
    final name = seriesName.trim();
    final vol = volumeNumber == volumeNumber.roundToDouble()
        ? volumeNumber.toInt().toString()
        : volumeNumber.toString();
    return '$name $vol';
  }

  /// Couverture d'un tome via Google Books + Open Library (requête série + numéro).
  static Future<String?> lookupVolumeCover({
    required String seriesName,
    required double volumeNumber,
    required BookSubcategory subcategory,
  }) async {
    final query = volumeSearchQuery(seriesName, volumeNumber);
    if (query.trim().length < 3) return null;

    final merged = <Map<String, String>>[];
    final seen = <String>{};
    for (final list in [
      await GoogleBooksService.search(query, maxResults: 12),
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
