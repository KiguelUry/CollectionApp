import 'package:flutter/material.dart';

enum CardSubcategory {
  pokemon,
  magic,
  yugioh,
  onepiece,
  lorcana,
  topps,
  panini,
  other;

  String get dbValue => name;

  String get label => switch (this) {
        CardSubcategory.pokemon => 'Pokémon',
        CardSubcategory.magic => 'Magic',
        CardSubcategory.yugioh => 'Yu-Gi-Oh!',
        CardSubcategory.onepiece => 'One Piece',
        CardSubcategory.lorcana => 'Lorcana (Disney)',
        CardSubcategory.topps => 'Topps',
        CardSubcategory.panini => 'Panini',
        CardSubcategory.other => 'Autre',
      };

  String get description => switch (this) {
        CardSubcategory.pokemon => 'Par bloc & série (TCGdex FR)',
        CardSubcategory.magic => 'Par bloc & série (Scryfall)',
        CardSubcategory.yugioh => 'Par ère & extension (YGOProDeck)',
        CardSubcategory.onepiece => 'Par type de booster (OPTCG)',
        CardSubcategory.lorcana => 'Par chapitre (Lorcast)',
        CardSubcategory.topps => 'Saisie manuelle — pas de catalogue',
        CardSubcategory.panini => 'Albums & stickers',
        CardSubcategory.other => 'Saisie manuelle',
      };

  IconData get icon => switch (this) {
        CardSubcategory.pokemon => Icons.catching_pokemon,
        CardSubcategory.magic => Icons.auto_fix_high,
        CardSubcategory.yugioh => Icons.auto_awesome,
        CardSubcategory.onepiece => Icons.sailing,
        CardSubcategory.lorcana => Icons.auto_awesome_motion,
        CardSubcategory.topps => Icons.sports_baseball_outlined,
        CardSubcategory.panini => Icons.collections_bookmark_outlined,
        CardSubcategory.other => Icons.style_outlined,
      };

  Color get color => switch (this) {
        CardSubcategory.pokemon => Colors.amber.shade800,
        CardSubcategory.magic => Colors.deepPurple,
        CardSubcategory.yugioh => Colors.indigo,
        CardSubcategory.onepiece => Colors.red.shade700,
        CardSubcategory.lorcana => Colors.lightBlue,
        CardSubcategory.topps => Colors.blue,
        CardSubcategory.panini => Colors.orange,
        CardSubcategory.other => Colors.blueGrey,
      };

  static List<CardSubcategory> get hubOrder => const [
        CardSubcategory.pokemon,
        CardSubcategory.magic,
        CardSubcategory.yugioh,
        CardSubcategory.onepiece,
        CardSubcategory.lorcana,
        CardSubcategory.topps,
        CardSubcategory.panini,
        CardSubcategory.other,
      ];

  bool get hasSetBrowser => switch (this) {
        CardSubcategory.pokemon ||
        CardSubcategory.magic ||
        CardSubcategory.yugioh ||
        CardSubcategory.onepiece ||
        CardSubcategory.lorcana =>
          true,
        _ => false,
      };

  bool get supportsCatalogSearch => switch (this) {
        CardSubcategory.pokemon ||
        CardSubcategory.magic ||
        CardSubcategory.yugioh ||
        CardSubcategory.onepiece ||
        CardSubcategory.lorcana =>
          true,
        _ => false,
      };

  static CardSubcategory fromDbValue(String? value) {
    if (value == null) return CardSubcategory.other;
    return CardSubcategory.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => CardSubcategory.other,
    );
  }
}
