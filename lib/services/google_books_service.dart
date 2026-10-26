import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_env.dart';
import 'open_library_service.dart';

/// Google Books API — meilleur taux de succès ISBN (FR, éditions récentes).
/// Clé : `GOOGLE_BOOKS_API_KEY` (.env / --dart-define) via [AppEnv].
class GoogleBooksService {
  static String? get _apiKey => AppEnv.googleBooksApiKey;

  static bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  static Uri _volumesUri(Map<String, String> query) {
    final params = Map<String, String>.from(query);
    final key = _apiKey;
    if (key != null && key.isNotEmpty) {
      params['key'] = key;
    } else if (kDebugMode) {
      debugPrint(
        'Google Books: GOOGLE_BOOKS_API_KEY absente → risque de 429',
      );
    }
    return Uri.https('www.googleapis.com', '/books/v1/volumes', params);
  }

  /// Résultat normalisé (même forme qu'Open Library + champs série).
  static Future<Map<String, String>?> lookupByIsbn(String isbn) async {
    for (final variant in OpenLibraryService.isbnLookupVariants(isbn)) {
      try {
        final url = _volumesUri({'q': 'isbn:$variant', 'maxResults': '3'});
        final response = await http.get(url);
        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>? ?? [];
        for (final raw in items) {
          final mapped = _mapVolume(raw as Map<String, dynamic>, variant);
          if (mapped != null) return mapped;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Google Books ISBN: $e');
      }
    }
    return null;
  }

  static Future<List<Map<String, String>>> search(
    String query, {
    int maxResults = 20,
    int startIndex = 0,
    String? langRestrict = 'fr',
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final params = <String, String>{
        'q': q,
        'maxResults': '${maxResults.clamp(1, 40)}',
        'startIndex': '${startIndex.clamp(0, 200)}',
        'orderBy': 'relevance',
      };
      if (langRestrict != null && langRestrict.isNotEmpty) {
        params['langRestrict'] = langRestrict;
      }
      final url = _volumesUri(params);
      final response = await http.get(url);
      if (response.statusCode == 429) {
        if (kDebugMode) debugPrint('Google Books 429 — rate limit');
        return [];
      }
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      final out = <Map<String, String>>[];
      for (final raw in items) {
        final mapped = _mapVolume(raw as Map<String, dynamic>, '');
        if (mapped != null) out.add(mapped);
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('Google Books search: $e');
      return [];
    }
  }

  /// 1–3 pages séquentielles (jamais en parallèle) pour une série entière.
  /// Évite le DDoS « 1 requête par tome ».
  static Future<List<Map<String, String>>> searchSeriesBatched(
    String seriesTitle, {
    String? author,
    int maxPages = 3,
    Duration pageDelay = const Duration(milliseconds: 600),
    String? langRestrict = 'fr',
  }) async {
    final name = seriesTitle.trim();
    if (name.length < 2) return [];
    final q = author != null && author.trim().isNotEmpty
        ? 'intitle:"$name" inauthor:"${author.trim()}"'
        : 'intitle:"$name"';
    final out = <Map<String, String>>[];
    final seen = <String>{};
    final pages = maxPages.clamp(1, 3);
    for (var page = 0; page < pages; page++) {
      if (page > 0) await Future<void>.delayed(pageDelay);
      final batch = await search(
        q,
        maxResults: 40,
        startIndex: page * 40,
        langRestrict: langRestrict,
      );
      if (batch.isEmpty) break;
      for (final hit in batch) {
        final title = hit['title']?.trim().toLowerCase() ?? '';
        if (title.isEmpty || !seen.add(title)) continue;
        out.add(hit);
      }
      if (batch.length < 40) break;
    }
    return out;
  }

  static Map<String, String>? _mapVolume(
    Map<String, dynamic> item,
    String isbnFallback,
  ) {
    final info = item['volumeInfo'] as Map<String, dynamic>?;
    if (info == null) return null;

    final title = info['title'] as String?;
    if (title == null || title.isEmpty) return null;

    final authors = (info['authors'] as List<dynamic>?)
        ?.map((a) => a.toString())
        .toList();
    final author = authors?.isNotEmpty == true ? authors!.first : '';

    final published = info['publishedDate'] as String? ?? '';
    final year = published.length >= 4 ? published.substring(0, 4) : published;

    final links = info['imageLinks'] as Map<String, dynamic>?;
    final rawImage =
        (links?['extraLarge'] ?? links?['large'] ?? links?['medium'] ??
                links?['thumbnail'] ?? links?['smallThumbnail'])
            ?.toString() ??
            '';
    final imageHttps = _hdGoogleCover(rawImage);

    String? isbn = isbnFallback;
    final ids = info['industryIdentifiers'] as List<dynamic>? ?? [];
    for (final raw in ids) {
      final id = raw as Map<String, dynamic>;
      final type = id['type'] as String? ?? '';
      final value = id['identifier']?.toString();
      if (value == null || value.isEmpty) continue;
      if (type == 'ISBN_13' || type == 'ISBN_10') {
        isbn = value;
        break;
      }
    }

    final result = <String, String>{
      'title': title,
      'author': author,
      'year': year,
      'image_url': imageHttps,
      'source': 'google_books',
      'google_books_id': item['id']?.toString() ?? '',
      if (published.isNotEmpty) 'published_date': published,
      if (isbn != null && isbn.isNotEmpty) 'isbn': isbn,
    };

    final subtitle = info['subtitle'] as String?;
    if (subtitle != null && subtitle.isNotEmpty) {
      result['subtitle'] = subtitle;
    }

    final publisher = info['publisher'] as String?;
    if (publisher != null && publisher.isNotEmpty) {
      result['publisher'] = publisher;
    }

    final avgRating = info['averageRating'];
    if (avgRating is num && avgRating > 0) {
      // Google Books = déjà /5.
      result['community_rating'] =
          avgRating.toDouble().clamp(0, 5).toStringAsFixed(2);
    }

    final langs = (info['language'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .join(',');
    if (langs != null && langs.isNotEmpty) {
      result['language'] = langs;
    }

    final seriesInfo = info['seriesInfo'] as Map<String, dynamic>?;
    if (seriesInfo != null) {
      final displayNum = seriesInfo['bookDisplayNumber']?.toString();
      if (displayNum != null && displayNum.isNotEmpty) {
        result['series_volume'] = displayNum;
      }
      final volumes = seriesInfo['volumeSeries'] as List<dynamic>?;
      if (volumes != null && volumes.isNotEmpty) {
        final first = volumes.first as Map<String, dynamic>;
        final order = first['orderNumber'];
        if (order != null) result['series_volume'] = order.toString();
      }
    }

    // Titre du type « Série, Tome 3 »
    final parsed = _parseSeriesFromTitle(title);
    if (parsed != null) {
      result.putIfAbsent('series_title', () => parsed.$1);
      result.putIfAbsent('series_volume', () => parsed.$2);
    }

    return result;
  }

  static (String, String)? _parseSeriesFromTitle(String title) {
    final patterns = [
      RegExp(r'^(.+?)\s*[,:\-–]\s*(?:tome|vol\.?|volume|#)\s*(\d+)', caseSensitive: false),
      RegExp(r'^(.+?)\s+\((\d+)\)$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(title.trim());
      if (m != null) {
        return (m.group(1)!.trim(), m.group(2)!);
      }
    }
    return null;
  }

  static String _hdGoogleCover(String url) {
    if (url.isEmpty) return '';
    var out = url.replaceFirst('http://', 'https://');
    out = out.replaceAll('&edge=curl', '');
    out = out.replaceAll(RegExp(r'[&?]edge=curl'), '');
    // zoom=2 = HD net sur mobile (évite flou zoom=1 / curl).
    if (out.contains('zoom=')) {
      out = out.replaceAll(RegExp(r'zoom=\d'), 'zoom=2');
    } else if (out.contains('books.google.com') ||
        out.contains('googleusercontent.com')) {
      out = out.contains('?') ? '$out&zoom=2' : '$out?zoom=2';
    }
    return out;
  }
}
