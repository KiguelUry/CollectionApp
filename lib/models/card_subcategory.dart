enum CardSubcategory {
  pokemon,
  yugioh,
  magic,
  topps,
  panini,
  other;

  String get dbValue => name;

  String get label => switch (this) {
        CardSubcategory.pokemon => 'Pokémon',
        CardSubcategory.yugioh => 'Yu-Gi-Oh!',
        CardSubcategory.magic => 'Magic',
        CardSubcategory.topps => 'Topps',
        CardSubcategory.panini => 'Panini',
        CardSubcategory.other => 'Autre',
      };

  static CardSubcategory fromDbValue(String? value) {
    if (value == null) return CardSubcategory.other;
    return CardSubcategory.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => CardSubcategory.other,
    );
  }
}
