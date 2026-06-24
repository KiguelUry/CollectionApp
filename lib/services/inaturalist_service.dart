import 'dart:convert';

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

  const WildlifeTaxonHit({
    required this.id,
    required this.name,
    this.commonName,
    this.wikipediaSummary,
    this.imageUrl,
    this.kingdom = '',
    this.iconicTaxon = '',
  });

  String get displayTitle => commonName?.isNotEmpty == true ? commonName! : name;

  String get kingdomFilter => WildlifeKingdom.fromIconic(iconicTaxon).dbValue;

  factory WildlifeTaxonHit.fromJson(Map<String, dynamic> json) {
    final defaultPhoto = json['default_photo'] as Map<String, dynamic>?;
    final wiki = json['wikipedia_summary'] as String?;
    return WildlifeTaxonHit(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      commonName: json['preferred_common_name'] as String?,
      wikipediaSummary: wiki,
      imageUrl: defaultPhoto?['medium_url'] as String? ??
          defaultPhoto?['url'] as String?,
      kingdom: json['kingdom'] as String? ?? '',
      iconicTaxon: json['iconic_taxon_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toItemMetadata() => {
        'inaturalist_id': id,
        'scientific_name': name,
        if (commonName != null) 'common_name': commonName,
        'wildlife_kingdom': kingdomFilter,
        if (wikipediaSummary != null) 'description': wikipediaSummary,
        'source': 'inaturalist',
      };
}

enum WildlifeKingdom {
  mammal,
  bird,
  fish,
  reptileAmphibian,
  insect,
  other;

  String get dbValue => switch (this) {
        WildlifeKingdom.mammal => 'mammal',
        WildlifeKingdom.bird => 'bird',
        WildlifeKingdom.fish => 'fish',
        WildlifeKingdom.reptileAmphibian => 'reptile_amphibian',
        WildlifeKingdom.insect => 'insect',
        WildlifeKingdom.other => 'other',
      };

  String get label => switch (this) {
        WildlifeKingdom.mammal => 'Mammifères',
        WildlifeKingdom.bird => 'Oiseaux',
        WildlifeKingdom.fish => 'Poissons',
        WildlifeKingdom.reptileAmphibian => 'Reptiles & amphibiens',
        WildlifeKingdom.insect => 'Insectes',
        WildlifeKingdom.other => 'Autres',
      };

  static WildlifeKingdom fromIconic(String iconic) {
    final k = iconic.toLowerCase();
    if (k.contains('mammal')) return WildlifeKingdom.mammal;
    if (k.contains('aves') || k.contains('bird')) return WildlifeKingdom.bird;
    if (k.contains('actinopterygii') || k.contains('fish')) {
      return WildlifeKingdom.fish;
    }
    if (k.contains('reptile') || k.contains('amphib')) {
      return WildlifeKingdom.reptileAmphibian;
    }
    if (k.contains('insect') || k.contains('arach')) {
      return WildlifeKingdom.insect;
    }
    return WildlifeKingdom.other;
  }

  static WildlifeKingdom? fromDb(String? value) {
    if (value == null) return null;
    for (final k in WildlifeKingdom.values) {
      if (k.dbValue == value) return k;
    }
    return null;
  }
}
