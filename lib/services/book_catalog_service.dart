import 'package:flutter/foundation.dart';

import '../models/book_subcategory.dart';
import 'book_intelligence_service.dart';
import 'google_books_service.dart';
import 'itunes_books_service.dart';
import 'open_library_service.dart';

/// Catalogue livres : Google Books + iTunes en priorité, Open Library en secours.
class BookCatalogService {
  static const _defaultLang = 'fr';

  /// Scan ISBN — Google Books → iTunes → Open Library.
  static Future<Map<String, String>?> lookupByIsbn(String isbn) async {
    Map<String, String>? result;

    try {
      result = await GoogleBooksService.lookupByIsbn(isbn);
    } catch (e) {
      if (kDebugMode) debugPrint('Google Books ISBN: $e');
    }

    if (result == null || (result['title'] ?? '').isEmpty) {
      try {
        result = await ItunesBooksService.lookupByIsbn(isbn);
      } catch (e) {
        if (kDebugMode) debugPrint('iTunes ISBN: $e');
      }
    }

    if (result == null || (result['title'] ?? '').isEmpty) {
      try {
        result = await OpenLibraryService.lookupByIsbn(isbn);
      } catch (e) {
        if (kDebugMode) debugPrint('OL ISBN: $e');
      }
    } else {
      // Enrichir couverture HD si iTunes ou OL complète
      final itunes = await ItunesBooksService.lookupByIsbn(isbn);
      if (itunes != null) result = _merge(result, itunes);
      final ol = await OpenLibraryService.lookupByIsbn(isbn);
      if (ol != null) result = _merge(result, ol);
    }

    return result;
  }

  static Future<List<Map<String, String>>> searchBooks(
    String query, {
    required BookSubcategory subcategory,
    BookSearchFilters filters = const BookSearchFilters(),
  }) async {
    try {
      var merged = await _searchMerged(
        query,
        subcategory: subcategory,
        filters: filters,
        frenchOnly: true,
      );
      if (merged.isEmpty) {
        merged = await _searchMerged(
          query,
          subcategory: subcategory,
          filters: filters,
          frenchOnly: false,
        );
      }
      return merged;
    } catch (e) {
      if (kDebugMode) debugPrint('BookCatalogService.searchBooks: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> _searchMerged(
    String query, {
    required BookSubcategory subcategory,
    required BookSearchFilters filters,
    required bool frenchOnly,
  }) async {
    final enhanced = _searchQueryForSubcategory(query, subcategory, frenchOnly);

    List<Map<String, String>> google = [];
    try {
      google = await GoogleBooksService.search(
        enhanced,
        maxResults: 25,
        langRestrict: frenchOnly ? _defaultLang : null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Google Books search: $e');
    }

    List<Map<String, String>> itunes = [];
    try {
      itunes = await ItunesBooksService.search(enhanced);
    } catch (e) {
      if (kDebugMode) debugPrint('iTunes books search: $e');
    }

    List<Map<String, String>> ol = [];
    if (google.isEmpty && itunes.isEmpty) {
      try {
        ol = await OpenLibraryService.searchBooks(
          query,
          subcategory: subcategory,
          frenchOnly: frenchOnly,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Open Library search: $e');
      }
    }

    final seen = <String>{};
    final merged = <Map<String, String>>[];
    for (final list in [google, itunes, ol]) {
      for (final b in list) {
        final title = b['title']?.trim();
        if (title == null || title.isEmpty) continue;
        if (frenchOnly && !_preferFrenchEdition(b)) continue;
        final key = title.toLowerCase();
        if (!seen.contains(key)) {
          seen.add(key);
          merged.add(b);
        } else {
          final idx = merged.indexWhere(
            (m) => (m['title'] ?? '').toLowerCase() == key,
          );
          if (idx >= 0) merged[idx] = _merge(merged[idx], b);
        }
      }
    }

    return BookIntelligenceService.enrichAndRank(
      merged,
      subcategory: subcategory,
      filters: filters.titleQuery.isEmpty &&
              filters.authorQuery.isEmpty &&
              filters.publisherQuery.isEmpty
          ? BookSearchFilters(titleQuery: query)
          : filters,
    )
        .map((e) => e.raw)
        .toList();
  }

  static String _searchQueryForSubcategory(
    String query,
    BookSubcategory sub,
    bool frenchOnly,
  ) {
    final q = query.trim();
    return switch (sub) {
      BookSubcategory.manga => '$q manga',
      BookSubcategory.comic => '$q bande dessinée',
      BookSubcategory.novel => frenchOnly ? '$q lang:fr' : q,
      _ => frenchOnly ? '$q lang:fr' : q,
    };
  }

  static bool _preferFrenchEdition(Map<String, String> hit) {
    final lang = (hit['language'] ?? hit['lang'] ?? '').toLowerCase();
    if (lang.isEmpty) return true;
    if (lang.contains('fr') || lang == 'fre' || lang == 'french') return true;
    if (lang.contains('en') || lang == 'eng') return false;
    return true;
  }

  static Map<String, String> _merge(
    Map<String, String>? base,
    Map<String, String> extra,
  ) {
    final out = <String, String>{...?base};
    for (final e in extra.entries) {
      if (e.value.isEmpty) continue;
      if (!out.containsKey(e.key) || (out[e.key] ?? '').isEmpty) {
        out[e.key] = e.value;
      }
    }
    final baseImg = out['image_url'] ?? '';
    final extraImg = extra['image_url'] ?? '';
    if (extraImg.isNotEmpty &&
        (_imageScore(extraImg) > _imageScore(baseImg))) {
      out['image_url'] = extraImg;
    }
    out['source'] = extra['source'] ?? out['source'] ?? 'merged';
    return out;
  }

  static int _imageScore(String url) {
    if (url.isEmpty) return 0;
    if (url.contains('600x600') || url.contains('zoom=0')) return 3;
    if (url.contains('itunes') || url.contains('google')) return 2;
    return 1;
  }

  static Map<String, dynamic> metadataFromLookup(Map<String, String> book) {
    return {
      if ((book['author'] ?? '').isNotEmpty) 'author': book['author']!,
      if ((book['year'] ?? '').isNotEmpty) 'year': book['year']!,
      if ((book['isbn'] ?? '').isNotEmpty) 'isbn': book['isbn']!,
      if ((book['publisher'] ?? '').isNotEmpty) 'publisher': book['publisher']!,
      if ((book['author_photo_url'] ?? '').isNotEmpty)
        'author_photo_url': book['author_photo_url']!,
      if ((book['google_books_id'] ?? '').isNotEmpty)
        'google_books_id': book['google_books_id']!,
      if ((book['itunes_id'] ?? '').isNotEmpty) 'itunes_id': book['itunes_id']!,
      if ((book['series_title'] ?? '').isNotEmpty)
        'series_title': book['series_title']!,
      if ((book['series_volume'] ?? '').isNotEmpty)
        'series_volume': book['series_volume']!,
      if ((book['subtitle'] ?? '').isNotEmpty) 'subtitle': book['subtitle']!,
      if ((book['source'] ?? '').isNotEmpty) 'catalog_source': book['source']!,
    };
  }

  /// Enrichit les résultats avec photo auteur (Open Library, secours).
  static Future<List<Map<String, String>>> enrichAuthorPhotos(
    List<Map<String, String>> books,
  ) async {
    final out = <Map<String, String>>[];
    for (final book in books) {
      final copy = Map<String, String>.from(book);
      final author = copy['author']?.trim();
      if (author != null &&
          author.isNotEmpty &&
          (copy['author_photo_url'] ?? '').isEmpty) {
        final photo = await OpenLibraryService.lookupAuthorPhotoUrl(author);
        if (photo != null && photo.isNotEmpty) {
          copy['author_photo_url'] = photo;
        }
      }
      out.add(copy);
    }
    return out;
  }
}
