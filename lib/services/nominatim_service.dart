import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Géocodage OpenStreetMap Nominatim (gratuit, sans clé API).
class NominatimService {
  static const _userAgent = 'Collectingo/1.1 (collection-app; contact@collectingo.app)';

  static Future<List<NominatimPlace>> searchPlaces(
    String query, {
    int limit = 8,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final url = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'json',
        'addressdetails': '1',
        'limit': '${limit.clamp(1, 10)}',
      });
      final response = await http.get(
        url,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((e) => NominatimPlace.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Nominatim: $e');
      return [];
    }
  }
}

class NominatimPlace {
  final String displayName;
  final double lat;
  final double lon;
  final String? type;

  const NominatimPlace({
    required this.displayName,
    required this.lat,
    required this.lon,
    this.type,
  });

  factory NominatimPlace.fromJson(Map<String, dynamic> json) {
    return NominatimPlace(
      displayName: json['display_name'] as String? ?? '',
      lat: double.tryParse('${json['lat']}') ?? 0,
      lon: double.tryParse('${json['lon']}') ?? 0,
      type: json['type'] as String?,
    );
  }

  Map<String, dynamic> toRestaurantMetadata() => {
        'osm_place': displayName,
        'latitude': lat,
        'longitude': lon,
        if (type != null) 'place_type': type,
      };
}
