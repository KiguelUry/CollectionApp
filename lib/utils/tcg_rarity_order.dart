import '../models/card_subcategory.dart';

/// Score de rareté croissant (commun → le plus rare).
int tcgRarityRank(String? rarity, CardSubcategory sub) {
  if (rarity == null || rarity.trim().isEmpty) return 8000;
  final r = _normalize(rarity);

  const tiers = <(int, List<String>)>[
    (95, ['promo', 'promotionnelle']),
    (90, ['mythic', 'mythique']),
    (85, ['hyper rare', 'special illustration', 'sar']),
    (80, ['secret rare', 'secrete', 'secrète']),
    (75, ['double rare', 'illustration rare', 'ultra rare', 'ultrarare']),
    (65, ['ex ', ' gx', ' vstar', ' v ', 'ir ']),
    (55, ['holo rare', 'rare holo', 'holograph', 'reverse holo', 'reverse']),
    (45, ['rare', 'rarete']),
    (30, ['uncommon', 'peu commune', 'peucommune', 'unc']),
    (10, ['common', 'commune']),
  ];

  for (final (score, keys) in tiers) {
    if (keys.any((k) => r.contains(k))) return score;
  }

  if (sub == CardSubcategory.pokemon) {
    if (r == 'commune' || r.startsWith('commune ')) return 10;
    if (r.contains('peu commune') || r.contains('peucommune')) return 30;
    if (r.contains('double rare')) return 75;
    if (r.contains('ultra rare')) return 76;
    if (r.contains('illustration rare')) return 77;
    if (r.contains('hyper rare')) return 85;
    if (r == 'rare' || r.startsWith('rare ')) return 45;
  }

  // Yu-Gi-Oh : super / ultra après rare
  if (sub == CardSubcategory.yugioh) {
    if (r.contains('secret')) return 75;
    if (r.contains('ultra')) return 55;
    if (r.contains('super')) return 45;
    if (r.contains('ultimate')) return 65;
  }

  return 500;
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll('é', 'e').replaceAll('è', 'e');

int compareTcgRarity(String? a, String? b, CardSubcategory sub) {
  final ra = tcgRarityRank(a, sub);
  final rb = tcgRarityRank(b, sub);
  if (ra != rb) return ra.compareTo(rb);
  return (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());
}

int tcgCardNumberSortKey(String? number) {
  if (number == null || number.trim().isEmpty) return 99999;
  final digits = RegExp(r'\d+').firstMatch(number)?.group(0);
  return int.tryParse(digits ?? '') ?? 99999;
}

void sortTcgCardsByRarity<T>(
  List<T> cards,
  CardSubcategory sub, {
  required String? Function(T) rarityOf,
  required String Function(T) tieBreaker,
  String? Function(T)? numberOf,
}) {
  cards.sort((a, b) {
    final c = compareTcgRarity(rarityOf(a), rarityOf(b), sub);
    if (c != 0) return c;
    if (numberOf != null) {
      final na = tcgCardNumberSortKey(numberOf(a));
      final nb = tcgCardNumberSortKey(numberOf(b));
      if (na != nb) return na.compareTo(nb);
    }
    return tieBreaker(a).compareTo(tieBreaker(b));
  });
}

List<String> sortRarityLabels(List<String> labels, CardSubcategory sub) {
  final copy = List<String>.from(labels);
  copy.sort(
    (a, b) => compareTcgRarity(a, b, sub),
  );
  return copy;
}
