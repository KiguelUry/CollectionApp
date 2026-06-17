/// Utilitaires cartes One Piece (OPTCG API).
abstract final class OnepieceCardUtils {
  /// Id catalogue unique : les parallèles partagent `card_set_id` mais pas `card_image_id`.
  static String catalogId(Map<String, dynamic> card) {
    final imageId = card['card_image_id']?.toString().trim() ?? '';
    if (imageId.isNotEmpty) return imageId;
    final setId = card['card_set_id']?.toString().trim() ?? '';
    if (setId.isNotEmpty) return setId;
    return card['card_id']?.toString() ?? card['id']?.toString() ?? '';
  }

  static bool isParallel(Map<String, dynamic> card) {
    final name = card['card_name']?.toString() ?? card['name']?.toString() ?? '';
    final imageId = card['card_image_id']?.toString() ?? '';
    return name.contains('(Parallel)') || RegExp(r'_p\d+$').hasMatch(imageId);
  }

  /// Rareté affichée : variante parallèle / étoile marquée « ★ ».
  static String? displayRarity(Map<String, dynamic> card) {
    final base = card['rarity']?.toString().trim() ?? '';
    if (base.isEmpty) return null;
    return isParallel(card) ? '$base ★' : base;
  }
}
