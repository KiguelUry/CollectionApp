import 'card_subcategory.dart';

/// Progression d’un set déduit des metadata collection (sans appel catalogue).
class TcgSetProgressRow {
  final String setKey;
  final String? setName;
  final int owned;

  const TcgSetProgressRow({
    required this.setKey,
    this.setName,
    required this.owned,
  });
}

/// Synthèse complétion pour un univers TCG.
class TcgSubcategoryStats {
  final CardSubcategory subcategory;
  final int ownedCards;
  final int setsTouched;
  final List<TcgSetProgressRow> topSets;

  const TcgSubcategoryStats({
    required this.subcategory,
    required this.ownedCards,
    required this.setsTouched,
    this.topSets = const [],
  });

  bool get hasCards => ownedCards > 0;
}
