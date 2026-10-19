/// Sélection du Top 10 automatique : pas d'extensions, pas de doublons.
class PantheonCandidate {
  final String id;
  final String title;
  final String? bggId;
  final bool isExpansion;
  final bool isWishlist;
  final double rating;
  final int plays;
  final double bggRating;

  const PantheonCandidate({
    required this.id,
    required this.title,
    this.bggId,
    this.isExpansion = false,
    this.isWishlist = false,
    this.rating = 0,
    this.plays = 0,
    this.bggRating = 0,
  });
}

List<String> pickAutoPantheonIds(
  Iterable<PantheonCandidate> items, {
  int limit = 10,
}) {
  final cap = limit.clamp(1, 20);
  final ranked = [...items.where((i) => !i.isWishlist && !i.isExpansion)];
  ranked.sort((a, b) {
    final ar = a.rating > 0 ? a.rating : -1;
    final br = b.rating > 0 ? b.rating : -1;
    final byRating = br.compareTo(ar);
    if (byRating != 0) return byRating;
    final byPlays = b.plays.compareTo(a.plays);
    if (byPlays != 0) return byPlays;
    final byBgg = b.bggRating.compareTo(a.bggRating);
    if (byBgg != 0) return byBgg;
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
    if (ids.length >= cap) break;
  }
  return ids;
}

/// Retire [itemId] (et [alsoRemove]) puis l'insère à [targetIndex].
/// Les occupants à partir de cette place descendent d'un rang. Rien n'est dupliqué.
List<String> placeInPantheon(
  List<String> ids,
  String itemId, {
  required int targetIndex,
  int cap = 20,
  Set<String> alsoRemove = const {},
}) {
  if (itemId.isEmpty) {
    return [for (final id in ids) if (id.isNotEmpty) id];
  }
  final drop = {itemId, ...alsoRemove};
  final next = <String>[
    for (final id in ids)
      if (id.isNotEmpty && !drop.contains(id)) id,
  ];
  var at = targetIndex;
  if (at < 0) at = 0;
  if (at > next.length) at = next.length;
  next.insert(at, itemId);
  if (next.length > cap) return next.sublist(0, cap);
  return next;
}
