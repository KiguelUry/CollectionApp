/// Sélection du Top 10 automatique : pas d'extensions, pas de doublons.
class PantheonCandidate {
  final String id;
  final String title;
  final String? bggId;
  final bool isExpansion;
  final bool isWishlist;
  final double rating;

  const PantheonCandidate({
    required this.id,
    required this.title,
    this.bggId,
    this.isExpansion = false,
    this.isWishlist = false,
    this.rating = 0,
  });
}

List<String> pickAutoPantheonIds(Iterable<PantheonCandidate> items) {
  final ranked = [...items.where((i) => !i.isWishlist && !i.isExpansion)];
  ranked.sort((a, b) {
    final byRating = b.rating.compareTo(a.rating);
    if (byRating != 0) return byRating;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  final seen = <String>{};
  final ids = <String>[];
  for (final item in ranked) {
    final bgg = item.bggId?.trim();
    final key = (bgg != null && bgg.isNotEmpty)
        ? 'bgg:$bgg'
        : 'title:${item.title.trim().toLowerCase()}';
    if (!seen.add(key)) continue;
    ids.add(item.id);
    if (ids.length == 10) break;
  }
  return ids;
}
