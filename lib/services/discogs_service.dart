import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/category_metadata.dart';

/// API Discogs — idéal pour vinyles (pochettes, pressages, catalogues).
/// Token personnel : https://www.discogs.com/settings/developers → `DISCOGS_TOKEN` dans `.env`
class DiscogsService {
  static const _userAgent =
      'Collectingo/1.0 +https://github.com/collectingo/collection-app';

  static String? get _token {
    final t = dotenv.env['DISCOGS_TOKEN']?.trim();
    return (t != null && t.isNotEmpty) ? t : null;
  }

  static bool get isConfigured => _token != null;

  static Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Discogs token=$_token',
      };

  static String? _formatParam(MediaFormat format) => switch (format) {
        MediaFormat.vinyl => 'Vinyl',
        MediaFormat.cd => 'CD',
        MediaFormat.cassette => 'Cassette',
      };

  static Future<List<Map<String, String>>> searchReleases(
    String query, {
    MediaFormat format = MediaFormat.vinyl,
    int limit = 20,
  }) async {
    if (!isConfigured) return [];
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final fmt = _formatParam(format);
      final url = Uri.https('api.discogs.com', '/database/search', {
        'q': q,
        'type': 'release',
        if (fmt != null) 'format': fmt,
        'per_page': '${limit.clamp(1, 50)}',
      });
      final response = await http.get(url, headers: _headers);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      final out = <Map<String, String>>[];
      for (final raw in results) {
        final mapped = _mapSearchResult(raw as Map<String, dynamic>);
        if (mapped != null) out.add(mapped);
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('Discogs search: $e');
      return [];
    }
  }

  static Future<Map<String, String>?> lookupByBarcode(
    String barcode, {
    MediaFormat format = MediaFormat.vinyl,
  }) async {
    if (!isConfigured) return null;
    final cleaned = barcode.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length < 8) return null;

    try {
      final fmt = _formatParam(format);
      final url = Uri.https('api.discogs.com', '/database/search', {
        'barcode': cleaned,
        'type': 'release',
        if (fmt != null) 'format': fmt,
        'per_page': '5',
      });
      final response = await http.get(url, headers: _headers);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      for (final raw in results) {
        final mapped = _mapSearchResult(raw as Map<String, dynamic>);
        if (mapped != null) {
          mapped['barcode'] = cleaned;
          return mapped;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Discogs barcode: $e');
    }
    return null;
  }

  static Map<String, String>? _mapSearchResult(Map<String, dynamic> r) {
    if (r['type'] != 'release') return null;

    final id = r['id'];
    if (id == null) return null;

    final fullTitle = r['title'] as String? ?? '';
    if (fullTitle.isEmpty) return null;

    var artist = '';
    var title = fullTitle;
    final dash = fullTitle.indexOf(' - ');
    if (dash > 0) {
      artist = fullTitle.substring(0, dash).trim();
      title = fullTitle.substring(dash + 3).trim();
    }

    final year = r['year']?.toString() ?? '';
    final thumb = r['thumb'] as String? ?? '';
    final cover = r['cover_image'] as String? ?? '';
    final imageUrl = cover.isNotEmpty ? cover : thumb;

    final labels = r['label'] as List<dynamic>? ?? [];
    final label = labels.isNotEmpty ? labels.first.toString() : '';

    final catnos = r['catno'] as String? ?? '';
    final country = r['country'] as String? ?? '';

    final formats = r['format'] as List<dynamic>? ?? [];
    final formatLabel =
        formats.isNotEmpty ? formats.map((e) => e.toString()).join(', ') : '';

    return {
      'title': title,
      'artist': artist,
      'year': year,
      'image_url': imageUrl,
      'discogs_release_id': '$id',
      if (label.isNotEmpty) 'label': label,
      if (catnos.isNotEmpty) 'catalog_number': catnos,
      if (country.isNotEmpty) 'country': country,
      if (formatLabel.isNotEmpty) 'pressing_format': formatLabel,
      'source': 'discogs',
    };
  }
}
