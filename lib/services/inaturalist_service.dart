import 'dart:convert';

import '../models/wildlife_taxonomy.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Taxons iNaturalist (API publique gratuite).
class INaturalistService {
  static const _base = 'https://api.inaturalist.org/v1';

  static Future<List<WildlifeTaxonHit>> searchSpecies(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final url = Uri.parse('$_base/taxa').replace(queryParameters: {
        'q': q,
        'rank': 'species',
        'per_page': '${limit.clamp(1, 30)}',
        'locale': 'fr',
      });
      final response = await http.get(
        url,
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      return results
          .map((r) => WildlifeTaxonHit.fromJson(r as Map<String, dynamic>))
          .where((h) => h.id > 0 && h.name.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('iNaturalist search: $e');
      return [];
    }
  }

  static Future<WildlifeTaxonHit?> fetchTaxon(int taxonId) async {
    try {
      final url = Uri.parse('$_base/taxa/$taxonId');
      final response = await http.get(
        url,
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return null;
      return WildlifeTaxonHit.fromJson(results.first as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) debugPrint('iNaturalist taxon: $e');
      return null;
    }
  }
}

class WildlifeTaxonHit {
  final int id;
  final String name;
  final String? commonName;
  final String? wikipediaSummary;
  final String? imageUrl;
  final String kingdom;
  final String iconicTaxon;
  final String? familyName;
  final String? genusName;

  const WildlifeTaxonHit({
    required this.id,
    required this.name,
    this.commonName,
    this.wikipediaSummary,
    this.imageUrl,
    this.kingdom = '',
    this.iconicTaxon = '',
    this.familyName,
    this.genusName,
  });

  String get displayTitle => commonName?.isNotEmpty == true ? commonName! : name;

  String get kingdomFilter => WildlifeKingdom.fromIconic(iconicTaxon).dbValue;

  factory WildlifeTaxonHit.fromJson(Map<String, dynamic> json) {
    final defaultPhoto = json['default_photo'] as Map<String, dynamic>?;
    final wiki = json['wikipedia_summary'] as String?;
    final ancestors = json['ancestors'] as List<dynamic>? ?? [];
    String? family;
    String? genus;
    for (final raw in ancestors) {
      if (raw is! Map) continue;
      final rank = (raw['rank'] as String?)?.toLowerCase();
      final n = raw['name'] as String?;
      if (n == null) continue;
      if (rank == 'family') family = n;
      if (rank == 'genus') genus = n;
    }
    return WildlifeTaxonHit(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      commonName: json['preferred_common_name'] as String?,
      wikipediaSummary: wiki,
      imageUrl: defaultPhoto?['medium_url'] as String? ??
          defaultPhoto?['url'] as String?,
      kingdom: json['kingdom'] as String? ?? '',
      iconicTaxon: json['iconic_taxon_name'] as String? ?? '',
      familyName: family,
      genusName: genus,
    );
  }

  Map<String, dynamic> toItemMetadata() {
    final kingdom = WildlifeKingdom.fromIconic(iconicTaxon);
    final taxonomy = WildlifeTaxonomy.buildTaxonomyMetadata(
      kingdom: kingdom,
      familyName: familyName,
      genus: genusName,
      scientificName: name,
    );
    return {
      'inaturalist_id': id,
      'scientific_name': name,
      if (commonName != null) 'common_name': commonName,
      ...taxonomy,
      if (wikipediaSummary != null) 'description': wikipediaSummary,
      'source': 'inaturalist',
    };
  }
}
