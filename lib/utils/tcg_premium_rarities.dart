import '../models/card_subcategory.dart';
import 'tcg_rarity_order.dart';

/// Raretés « premium » affichées en priorité (évite de charger les communes).
List<String> premiumRarityTiers(CardSubcategory sub) {
  return switch (sub) {
    CardSubcategory.magic => const [
        'mythic',
        'rare',
        'uncommon',
        'common',
      ],
    CardSubcategory.pokemon => const [
        'Hyper rare',
        'Illustration rare',
        'Ultra rare',
        'Double rare',
        'Rare',
        'Peu Commune',
        'Commune',
      ],
    CardSubcategory.yugioh => const [
        'Secret Rare',
        'Ultra Rare',
        'Super Rare',
        'Rare',
        'Common',
      ],
    CardSubcategory.lorcana => const [
        'Enchanted',
        'Legendary',
        'Super Rare',
        'Rare',
        'Uncommon',
        'Common',
      ],
    CardSubcategory.onepiece => const [
        'Secret Rare',
        'Super Rare',
        'Rare',
        'Uncommon',
        'Common',
      ],
    _ => const ['Rare', 'Uncommon', 'Common'],
  };
}

/// Rareté la plus élevée connue dans une liste (pour sélection par défaut).
String? defaultPremiumRarity(
  Iterable<String> available,
  CardSubcategory sub,
) {
  final tiers = premiumRarityTiers(sub);
  final lower = available.map((e) => e.toLowerCase()).toSet();
  for (var i = tiers.length - 1; i >= 0; i--) {
    final t = tiers[i].toLowerCase();
    final match = available.where((a) => a.toLowerCase().contains(t));
    if (match.isNotEmpty) return match.first;
    if (lower.contains(t)) {
      return available.firstWhere((a) => a.toLowerCase() == t);
    }
  }
  final sorted = sortRarityLabels(available.toList(), sub);
  return sorted.isNotEmpty ? sorted.last : null;
}

bool rarityMatchesTier(String? cardRarity, String tier) {
  if (cardRarity == null || cardRarity.isEmpty) return false;
  final r = cardRarity.toLowerCase();
  final t = tier.toLowerCase();
  return r == t || r.contains(t);
}
