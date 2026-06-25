import 'package:flutter/material.dart';

import '../services/inaturalist_service.dart';

/// Tuile de navigation taxonomique (famille, groupe de genres…).
class WildlifeTaxonNode {
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const WildlifeTaxonNode({
    required this.id,
    required this.label,
    required this.icon,
    this.color = const Color(0xFF39FF14),
  });
}

/// Arborescence Pokédex à 4 niveaux (Règne → Famille → Groupe → Espèce).
abstract final class WildlifeTaxonomy {
  static const otherFamilyId = 'other';
  static const otherGenusGroupId = 'other';

  static List<WildlifeTaxonNode> familiesFor(WildlifeKingdom kingdom) {
    return switch (kingdom) {
      WildlifeKingdom.mammal => const [
          WildlifeTaxonNode(
            id: 'felidae',
            label: 'Félins',
            icon: Icons.pets,
            color: Color(0xFFFF9100),
          ),
          WildlifeTaxonNode(
            id: 'canidae',
            label: 'Canidés',
            icon: Icons.cruelty_free,
            color: Color(0xFF8D6E63),
          ),
          WildlifeTaxonNode(
            id: 'cetacea',
            label: 'Cétacés',
            icon: Icons.water,
            color: Color(0xFF29B6F6),
          ),
          WildlifeTaxonNode(
            id: 'ursidae',
            label: 'Ours',
            icon: Icons.forest,
            color: Color(0xFF6D4C41),
          ),
          WildlifeTaxonNode(
            id: 'cervidae',
            label: 'Cervidés',
            icon: Icons.park,
            color: Color(0xFF66BB6A),
          ),
          WildlifeTaxonNode(
            id: otherFamilyId,
            label: 'Autres mammifères',
            icon: Icons.grid_view_rounded,
          ),
        ],
      WildlifeKingdom.bird => const [
          WildlifeTaxonNode(
            id: 'raptors',
            label: 'Rapaces',
            icon: Icons.air,
            color: Color(0xFF5C6BC0),
          ),
          WildlifeTaxonNode(
            id: 'passerines',
            label: 'Passereaux',
            icon: Icons.flutter_dash,
            color: Color(0xFF26A69A),
          ),
          WildlifeTaxonNode(
            id: 'waterfowl',
            label: 'Oiseaux d\'eau',
            icon: Icons.waves,
            color: Color(0xFF42A5F5),
          ),
          WildlifeTaxonNode(
            id: otherFamilyId,
            label: 'Autres oiseaux',
            icon: Icons.grid_view_rounded,
          ),
        ],
      WildlifeKingdom.fish => const [
          WildlifeTaxonNode(
            id: 'sharks',
            label: 'Requins & raies',
            icon: Icons.water,
            color: Color(0xFF546E7A),
          ),
          WildlifeTaxonNode(
            id: 'reef_fish',
            label: 'Poissons récifaux',
            icon: Icons.bubble_chart,
            color: Color(0xFF26C6DA),
          ),
          WildlifeTaxonNode(
            id: otherFamilyId,
            label: 'Autres poissons',
            icon: Icons.grid_view_rounded,
          ),
        ],
      WildlifeKingdom.reptileAmphibian => const [
          WildlifeTaxonNode(
            id: 'snakes',
            label: 'Serpents',
            icon: Icons.timeline,
            color: Color(0xFF7CB342),
          ),
          WildlifeTaxonNode(
            id: 'lizards',
            label: 'Lézards',
            icon: Icons.grass,
            color: Color(0xFF9CCC65),
          ),
          WildlifeTaxonNode(
            id: 'amphibians',
            label: 'Amphibiens',
            icon: Icons.opacity,
            color: Color(0xFF4DD0E1),
          ),
          WildlifeTaxonNode(
            id: otherFamilyId,
            label: 'Autres',
            icon: Icons.grid_view_rounded,
          ),
        ],
      WildlifeKingdom.insect => const [
          WildlifeTaxonNode(
            id: 'butterflies',
            label: 'Papillons',
            icon: Icons.auto_awesome,
            color: Color(0xFFEC407A),
          ),
          WildlifeTaxonNode(
            id: 'beetles',
            label: 'Coléoptères',
            icon: Icons.bug_report,
            color: Color(0xFF8E24AA),
          ),
          WildlifeTaxonNode(
            id: otherFamilyId,
            label: 'Autres insectes',
            icon: Icons.grid_view_rounded,
          ),
        ],
      WildlifeKingdom.other => const [
          WildlifeTaxonNode(
            id: otherFamilyId,
            label: 'Divers',
            icon: Icons.hub,
          ),
        ],
    };
  }

  static List<WildlifeTaxonNode> genusGroupsFor(String familyId) {
    return switch (familyId) {
      'felidae' => const [
          WildlifeTaxonNode(
            id: 'small_cats',
            label: 'Chats',
            icon: Icons.pets,
            color: Color(0xFFFFB74D),
          ),
          WildlifeTaxonNode(
            id: 'big_cats',
            label: 'Grands félins',
            icon: Icons.shield_moon,
            color: Color(0xFFFF6F00),
          ),
          WildlifeTaxonNode(
            id: otherGenusGroupId,
            label: 'Autres félins',
            icon: Icons.more_horiz,
          ),
        ],
      'canidae' => const [
          WildlifeTaxonNode(
            id: 'dogs',
            label: 'Chiens & renards',
            icon: Icons.pets,
          ),
          WildlifeTaxonNode(
            id: 'wild_canids',
            label: 'Canidés sauvages',
            icon: Icons.nightlight_round,
          ),
          WildlifeTaxonNode(
            id: otherGenusGroupId,
            label: 'Autres',
            icon: Icons.more_horiz,
          ),
        ],
      'cetacea' => const [
          WildlifeTaxonNode(
            id: 'whales',
            label: 'Baleines',
            icon: Icons.water,
          ),
          WildlifeTaxonNode(
            id: 'dolphins',
            label: 'Dauphins',
            icon: Icons.sailing,
          ),
          WildlifeTaxonNode(
            id: otherGenusGroupId,
            label: 'Autres',
            icon: Icons.more_horiz,
          ),
        ],
      _ => const [
          WildlifeTaxonNode(
            id: otherGenusGroupId,
            label: 'Toutes les espèces',
            icon: Icons.list_alt,
          ),
        ],
    };
  }

  static String? familyLabel(String? familyId, WildlifeKingdom kingdom) {
    if (familyId == null) return null;
    for (final f in familiesFor(kingdom)) {
      if (f.id == familyId) return f.label;
    }
    return null;
  }

  static String? genusGroupLabel(String familyId, String? groupId) {
    if (groupId == null) return null;
    for (final g in genusGroupsFor(familyId)) {
      if (g.id == groupId) return g.label;
    }
    return null;
  }

  /// Infère la famille à partir du nom iNaturalist (ex. « Felidae »).
  static String familyIdFromINat(
    WildlifeKingdom kingdom,
    String? familyName,
  ) {
    final n = familyName?.toLowerCase().trim() ?? '';
    if (n.isEmpty) return otherFamilyId;

    bool has(String s) => n.contains(s);

    return switch (kingdom) {
      WildlifeKingdom.mammal => () {
          if (has('felid')) return 'felidae';
          if (has('canid')) return 'canidae';
          if (has('cetace') || has('delphin')) return 'cetacea';
          if (has('ursid') || has('bear')) return 'ursidae';
          if (has('cervid') || has('deer')) return 'cervidae';
          return otherFamilyId;
        }(),
      WildlifeKingdom.bird => () {
          if (has('accipitr') || has('falcon') || has('strigid')) {
            return 'raptors';
          }
          if (has('anatid') || has('larid')) return 'waterfowl';
          if (has('passer')) return 'passerines';
          return otherFamilyId;
        }(),
      WildlifeKingdom.fish => () {
          if (has('carchar') || has('rajiform')) return 'sharks';
          if (has('pomacent') || has('chaetodont')) return 'reef_fish';
          return otherFamilyId;
        }(),
      WildlifeKingdom.reptileAmphibian => () {
          if (has('serpent') || has('viper')) return 'snakes';
          if (has('lacert') || has('iguan')) return 'lizards';
          if (has('anura') || has('salamand')) return 'amphibians';
          return otherFamilyId;
        }(),
      WildlifeKingdom.insect => () {
          if (has('lepidopter') || has('papilion')) return 'butterflies';
          if (has('coleopter')) return 'beetles';
          return otherFamilyId;
        }(),
      WildlifeKingdom.other => otherFamilyId,
    };
  }

  /// Infère le groupe de genres (ex. Panthera → grands félins).
  static String genusGroupIdFromINat(String familyId, String? genus) {
    final g = genus?.toLowerCase().trim() ?? '';
    if (g.isEmpty) return otherGenusGroupId;

    return switch (familyId) {
      'felidae' => () {
          const big = {
            'panthera',
            'acinonyx',
            'neofelis',
            'pardofelis',
          };
          if (big.contains(g)) return 'big_cats';
          return 'small_cats';
        }(),
      'canidae' => () {
          const domestic = {'canis', 'vulpes'};
          if (domestic.contains(g)) return 'dogs';
          return 'wild_canids';
        }(),
      'cetacea' => () {
          if (g.contains('balaen') || g == 'megaptera') return 'whales';
          if (g.contains('delphin') || g == 'tursiops') return 'dolphins';
          return otherGenusGroupId;
        }(),
      _ => otherGenusGroupId,
    };
  }

  static String genusFromScientificName(String scientificName) {
    final parts = scientificName.trim().split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first.toLowerCase() : '';
  }

  static Map<String, String> buildTaxonomyMetadata({
    required WildlifeKingdom kingdom,
    String? familyName,
    String? genus,
    String? scientificName,
  }) {
    final genusName = genus?.isNotEmpty == true
        ? genus!
        : genusFromScientificName(scientificName ?? '');
    final familyId = familyIdFromINat(kingdom, familyName);
    final genusGroupId = genusGroupIdFromINat(familyId, genusName);

    return {
      'wildlife_kingdom': kingdom.dbValue,
      'wildlife_family': familyId,
      'wildlife_genus_group': genusGroupId,
      if (familyName != null && familyName.isNotEmpty) 'inat_family': familyName,
      if (genusName.isNotEmpty) 'inat_genus': genusName,
    };
  }
}
