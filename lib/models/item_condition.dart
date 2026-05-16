/// État général d'un objet dans la collection (toutes catégories).
enum ItemCondition {
  neuf,
  tresBon,
  bon,
  correct,
  use;

  String get dbValue => switch (this) {
        ItemCondition.neuf => 'neuf',
        ItemCondition.tresBon => 'tres_bon',
        ItemCondition.bon => 'bon',
        ItemCondition.correct => 'correct',
        ItemCondition.use => 'use',
      };

  String get label => switch (this) {
        ItemCondition.neuf => 'Neuf',
        ItemCondition.tresBon => 'Très bon état',
        ItemCondition.bon => 'Bon état',
        ItemCondition.correct => 'État correct',
        ItemCondition.use => 'Usé',
      };

  static ItemCondition? fromDbValue(String? value) {
    if (value == null || value.isEmpty) return null;
    return ItemCondition.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => ItemCondition.bon,
    );
  }
}
