import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/book_subcategory.dart';
import '../models/series_search_hit.dart';
import '../utils/book_title_parser.dart';
import '../utils/cover_image_url.dart';
import '../utils/search_relevance.dart';

/// API gratuite Open Library — équivalent « catalogue » pour les livres.
/// https://openlibrary.org/developers/api
class OpenLibraryService {
  static final _authorPhotoCache = <String, String?>{};

  static Future<List<Map<String, String>>> searchBooks(
    String query, {
    required BookSubcategory subcategory,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];

    try {
      final params = {
        ...subcategory.openLibraryQueryParams(trimmed),
        'limit': '40',
        'fields':
            'key,title,author_name,first_publish_year,cover_i,ratings_average,ratings_count,subject,language',
      };
      final url = Uri.https('openlibrary.org', '/search.json', params);
      final response = await http.get(url);

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['docs'] as List<dynamic>? ?? [];

      final results = <Map<String, String>>[];
      for (final raw in docs) {
        final doc = raw as Map<String, dynamic>;
        if (!subcategory.matchesOpenLibraryDoc(doc)) continue;

        final title = doc['title'] as String? ?? 'Sans titre';
        final authors = doc['author_name'] as List<dynamic>?;
        final author = authors?.isNotEmpty == true
            ? authors!.first.toString()
            : 'Auteur inconnu';
        final year = doc['first_publish_year']?.toString() ?? '';
        final coverId = doc['cover_i']?.toString();
        final imageUrl = coverId != null
            ? openLibraryCoverUrl(coverId, size: CoverSize.medium)
            : '';
        final ratingAvg = (doc['ratings_average'] as num?)?.toDouble();
        final ratingCount = (doc['ratings_count'] as int?) ?? 0;

        results.add({
          'key': doc['key']?.toString() ?? '',
          'title': title,
          'author': author,
          'year': year,
          'image_url': imageUrl,
          if (ratingAvg != null) 'rating_avg': ratingAvg.toStringAsFixed(1),
          'rating_count': ratingCount.toString(),
        });
      }

      sortByScore(
        results,
        (b) {
          final rel = titleRelevanceScore(b['title']!, trimmed);
          final authorRel = titleRelevanceScore(b['author'] ?? '', trimmed);
          final count = int.tryParse(b['rating_count'] ?? '0') ?? 0;
          final avg = double.tryParse(b['rating_avg'] ?? '') ?? 0;
          final popularity = (count * avg * 10).round();
          return rel * 10 + authorRel * 5 + popularity;
        },
      );

      return results.take(20).toList();
    } catch (e) {
      debugPrint('Erreur recherche Open Library: $e');
      return [];
    }
  }

  /// Variantes ISBN à tester (EAN-13 scanné, ISBN-10, etc.).
  static List<String> isbnLookupVariants(String isbn) {
    final cleaned = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (cleaned.length < 10) return const [];

    final variants = <String>{cleaned};
    if (cleaned.length == 13 && cleaned.startsWith('978')) {
      final isbn10 = _isbn13ToIsbn10(cleaned);
      if (isbn10 != null) variants.add(isbn10);
    }
    if (cleaned.length == 10) {
      final isbn13 = _isbn10ToIsbn13(cleaned);
      if (isbn13 != null) variants.add(isbn13);
    }
    return variants.toList();
  }

  static String? _isbn13ToIsbn10(String isbn13) {
    if (isbn13.length != 13 || !isbn13.startsWith('978')) return null;
    final core = isbn13.substring(3, 12);
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(core[i]) * (10 - i);
    }
    final check = (11 - (sum % 11)) % 11;
    final checkChar = check == 10 ? 'X' : '$check';
    return '$core$checkChar';
  }

  static String? _isbn10ToIsbn13(String isbn10) {
    if (isbn10.length != 10) return null;
    final core = '978${isbn10.substring(0, 9)}';
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = int.parse(core[i]);
      sum += digit * (i.isEven ? 1 : 3);
    }
    final check = (10 - (sum % 10)) % 10;
    return '$core$check';
  }

  static Map<String, String>? _mapOlBookData(
    Map<String, dynamic> book,
    String isbn,
  ) {
    final title = book['title'] as String?;
    if (title == null || title.isEmpty) return null;

    final authors = book['authors'] as List<dynamic>?;
    final author = authors?.isNotEmpty == true
        ? (authors!.first as Map)['name']?.toString() ?? ''
        : '';

    final covers = book['cover'] as Map<String, dynamic>?;
    final imageUrl = covers?['medium'] as String? ?? '';

    final publish = book['publish_date'] as String?;
    final year = publish != null && publish.length >= 4
        ? publish.substring(0, 4)
        : '';

    return {
      'title': title,
      'author': author,
      'isbn': isbn,
      'year': year,
      'image_url': imageUrl,
    };
  }

  static Map<String, String>? _mapSearchDoc(
    Map<String, dynamic> doc,
    String isbn,
  ) {
    final title = doc['title'] as String?;
    if (title == null || title.isEmpty) return null;

    final authors = doc['author_name'] as List<dynamic>?;
    final author = authors?.isNotEmpty == true
        ? authors!.first.toString()
        : '';
    final year = doc['first_publish_year']?.toString() ?? '';
    final coverId = doc['cover_i']?.toString();
    final imageUrl = coverId != null
        ? openLibraryCoverUrl(coverId, size: CoverSize.medium)
        : '';

    return {
      'title': title,
      'author': author,
      'isbn': isbn,
      'year': year,
      'image_url': imageUrl,
    };
  }

  static BookSubcategory? guessSubcategoryFromDoc(Map<String, dynamic> doc) {
    final subjects = (doc['subject'] as List<dynamic>?)
            ?.map((s) => s.toString().toLowerCase())
            .toList() ??
        const <String>[];

    bool has(String needle) => subjects.any((s) => s.contains(needle));

    if (has('manga')) return BookSubcategory.manga;
    if (has('comic') ||
        has('graphic novel') ||
        has('bande dessinée') ||
        has('bandes dessinées')) {
      return BookSubcategory.comic;
    }
    if (has('fiction') || has('roman') || has('literature')) {
      return BookSubcategory.novel;
    }
    return null;
  }

  /// Recherche par code ISBN/EAN (scan code-barres).
  static Future<Map<String, String>?> lookupByIsbn(String isbn) async {
    final variants = isbnLookupVariants(isbn);
    if (variants.isEmpty) return null;

    final primary = variants.first;

    try {
      final bibkeys = variants.map((v) => 'ISBN:$v').join(',');
      final url = Uri.https('openlibrary.org', '/api/books', {
        'bibkeys': bibkeys,
        'format': 'json',
        'jscmd': 'data',
      });
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        for (final variant in variants) {
          final book = data['ISBN:$variant'] as Map<String, dynamic>?;
          if (book != null) {
            final mapped = _mapOlBookData(book, primary);
            if (mapped != null) return mapped;
          }
        }
      }

      final searchUrl = Uri.https('openlibrary.org', '/search.json', {
        'q': 'isbn:$primary',
        'limit': '3',
        'fields':
            'key,title,author_name,first_publish_year,cover_i,subject,isbn',
      });
      final searchRes = await http.get(searchUrl);
      if (searchRes.statusCode == 200) {
        final data = jsonDecode(searchRes.body) as Map<String, dynamic>;
        final docs = data['docs'] as List<dynamic>? ?? [];
        for (final raw in docs) {
          final doc = raw as Map<String, dynamic>;
          final mapped = _mapSearchDoc(doc, primary);
          if (mapped != null) {
            final guess = guessSubcategoryFromDoc(doc);
            if (guess != null) {
              mapped['subcategory_hint'] = guess.dbValue;
            }
            return mapped;
          }
        }
      }
    } catch (e) {
      debugPrint('ISBN lookup: $e');
    }
    return null;
  }

  /// Recherche des séries par nom (ex. « Thorgal », « Naruto »).
  static Future<List<SeriesSearchHit>> searchSeriesCandidates(
    String query, {
    required BookSubcategory subcategory,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];

    try {
      final params = {
        ...subcategory.openLibraryQueryParams(trimmed),
        'limit': '60',
        'fields':
            'key,title,author_name,first_publish_year,cover_i,subject',
      };
      final url = Uri.https('openlibrary.org', '/search.json', params);
      final response = await http.get(url);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['docs'] as List<dynamic>? ?? [];
      final qLower = trimmed.toLowerCase();

      final groups = <String, _SeriesGroupAccumulator>{};

      for (final raw in docs) {
        final doc = raw as Map<String, dynamic>;
        if (!subcategory.matchesOpenLibraryDoc(doc)) continue;

        final title = doc['title'] as String? ?? '';
        if (title.isEmpty) continue;

        final parsed = BookTitleParser.parse(title);
        String? seriesName;
        double? vol;

        if (parsed.hasSeries) {
          seriesName = parsed.seriesName;
          vol = parsed.volumeNumber;
        } else {
          final tLower = title.toLowerCase();
          if (tLower.contains(qLower) ||
              (qLower.length >= 3 && tLower.startsWith(qLower))) {
            seriesName = title.split(RegExp(r'[:\-,–]')).first.trim();
          }
        }

        if (seriesName == null || seriesName.length < 2) continue;
        if (!seriesName.toLowerCase().contains(qLower) &&
            !BookTitleParser.seriesNamesMatch(seriesName, trimmed)) {
          continue;
        }

        final coverId = doc['cover_i']?.toString();
        final coverUrl = coverId != null
            ? openLibraryCoverUrl(coverId, size: CoverSize.medium)
            : null;
        final authors = doc['author_name'] as List<dynamic>?;
        final author = authors?.isNotEmpty == true
            ? authors!.first.toString()
            : null;

        final key = seriesName.toLowerCase();
        (groups.putIfAbsent(
          key,
          () => _SeriesGroupAccumulator(seriesName!),
        ))
            .add(
          volume: vol,
          coverUrl: coverUrl,
          author: author,
        );
      }

      if (!groups.containsKey(qLower)) {
        groups[qLower] = _SeriesGroupAccumulator(trimmed);
      }

      final hits = groups.values.map((g) => g.build()).toList();
      sortByScore(
        hits,
        (h) => titleRelevanceScore(h.name, trimmed) * 10 +
            (h.estimatedVolumes ?? 0),
      );
      return hits.take(15).toList();
    } catch (e) {
      debugPrint('searchSeriesCandidates: $e');
      return [];
    }
  }

  /// Estime le nombre de tomes d'une série via les titres Open Library.
  static Future<int?> estimateSeriesVolumeCount(
    String seriesName,
    BookSubcategory subcategory,
  ) async {
    final name = seriesName.trim();
    if (name.length < 2) return null;

    try {
      final params = {
        ...subcategory.openLibraryQueryParams(name),
        'limit': '50',
        'fields': 'title',
      };
      final url = Uri.https('openlibrary.org', '/search.json', params);
      final response = await http.get(url);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['docs'] as List<dynamic>? ?? [];

      var maxVol = 0;
      for (final raw in docs) {
        final title = (raw as Map<String, dynamic>)['title'] as String?;
        if (title == null) continue;
        final parsed = BookTitleParser.parse(title);
        if (!parsed.hasVolume || parsed.seriesName == null) continue;
        if (!BookTitleParser.seriesNamesMatch(parsed.seriesName!, name)) {
          continue;
        }
        final v = parsed.volumeNumber!.ceil();
        if (v > maxVol) maxVol = v;
      }
      return maxVol > 0 ? maxVol : null;
    } catch (e) {
      debugPrint('estimateSeriesVolumeCount: $e');
      return null;
    }
  }

  /// Couverture d'un tome précis (ex. Thorgal 1).
  static Future<String?> lookupVolumeCover(
    String seriesName,
    double volumeNumber,
    BookSubcategory subcategory,
  ) async {
    final name = seriesName.trim();
    if (name.length < 2) return null;

    final volLabel = volumeNumber == volumeNumber.roundToDouble()
        ? volumeNumber.toInt().toString()
        : volumeNumber.toString();

    final queries = [
      '$name $volLabel',
      '$name tome $volLabel',
      '$name vol. $volLabel',
    ];

    for (final q in queries) {
      final hits = await searchBooks(q, subcategory: subcategory);
      for (final hit in hits) {
        final title = hit['title'] ?? '';
        final img = hit['image_url'] ?? '';
        if (img.isEmpty) continue;

        final parsed = BookTitleParser.parse(title);
        if (parsed.hasSeries &&
            parsed.seriesName != null &&
            BookTitleParser.seriesNamesMatch(parsed.seriesName!, name) &&
            parsed.volumeNumber != null &&
            (parsed.volumeNumber! - volumeNumber).abs() < 0.01) {
          return coverUrlForDisplay(img, large: true);
        }
      }
      if (hits.isNotEmpty) {
        final firstImg = hits.first['image_url'] ?? '';
        if (firstImg.isNotEmpty &&
            titleRelevanceScore(hits.first['title'] ?? '', name) >= 4) {
          return coverUrlForDisplay(firstImg, large: true);
        }
      }
    }
    return null;
  }

  /// Photo auteur Open Library (cache mémoire).
  static Future<String?> lookupAuthorPhotoUrl(String authorName) async {
    final key = authorName.trim().toLowerCase();
    if (key.length < 2) return null;
    if (_authorPhotoCache.containsKey(key)) return _authorPhotoCache[key];

    try {
      final url = Uri.https('openlibrary.org', '/search/authors.json', {
        'q': authorName.trim(),
        'limit': '5',
      });
      final response = await http.get(url);
      if (response.statusCode != 200) {
        _authorPhotoCache[key] = null;
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['docs'] as List<dynamic>? ?? [];

      for (final raw in docs) {
        final doc = raw as Map<String, dynamic>;
        final name = doc['name'] as String? ?? '';
        if (titleRelevanceScore(name, authorName) < 3) continue;

        final authorKey = doc['key'] as String?;
        if (authorKey == null || !authorKey.startsWith('/authors/')) continue;

        final olid = authorKey.replaceFirst('/authors/', '');
        final photo = openLibraryAuthorPhotoUrl(olid, size: CoverSize.medium);
        _authorPhotoCache[key] = photo;
        return photo;
      }
    } catch (e) {
      debugPrint('lookupAuthorPhotoUrl: $e');
    }
    _authorPhotoCache[key] = null;
    return null;
  }
}

class _SeriesGroupAccumulator {
  final String name;
  final Set<int> _volumes = {};
  String? _coverUrl;
  String? _author;

  _SeriesGroupAccumulator(this.name);

  void add({
    double? volume,
    String? coverUrl,
    String? author,
  }) {
    if (volume != null) _volumes.add(volume.ceil());
    if ((_coverUrl == null || _coverUrl!.isEmpty) &&
        coverUrl != null &&
        coverUrl.isNotEmpty) {
      _coverUrl = coverUrl;
    }
    _author ??= author;
  }

  SeriesSearchHit build() {
    int? maxVol;
    if (_volumes.isNotEmpty) {
      maxVol = _volumes.reduce((a, b) => a > b ? a : b);
    }
    return SeriesSearchHit(
      name: name,
      coverUrl: _coverUrl,
      estimatedVolumes: maxVol,
      author: _author,
    );
  }
}
