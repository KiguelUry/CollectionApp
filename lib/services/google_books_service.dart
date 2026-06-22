import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'open_library_service.dart';

/// Google Books API — meilleur taux de succès ISBN (FR, éditions récentes).
/// Clé optionnelle : `GOOGLE_BOOKS_API_KEY` dans `.env`.
class GoogleBooksService {
  static String? get _apiKey {
    final k = dotenv.env['GOOGLE_BOOKS_API_KEY']?.trim();
    return (k != null && k.isNotEmpty) ? k : null;
  }

  static Uri _volumesUri(Map<String, String> query) {
    if (_apiKey != null) query['key'] = _apiKey!;
    return Uri.https('www.googleapis.com', '/books/v1/volumes', query);
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
    String? langRestrict = 'fr',
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final params = <String, String>{
        'q': q,
        'maxResults': '$maxResults',
        'orderBy': 'relevance',
      };
      if (langRestrict != null && langRestrict.isNotEmpty) {
        params['langRestrict'] = langRestrict;
      }
      final url = _volumesUri(params);
      final response = await http.get(url);
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
    if (out.contains('zoom=')) {
      out = out.replaceAll(RegExp(r'zoom=\d'), 'zoom=0');
    } else if (out.contains('books.google.com')) {
      out = '$out&zoom=0';
    }
    return out;
  }
}
