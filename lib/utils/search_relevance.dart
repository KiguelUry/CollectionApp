/// Score de pertinence texte (plus haut = meilleur match).
int titleRelevanceScore(String title, String query) {
  final t = _normalize(title);
  final q = _normalize(query);
  if (q.isEmpty) return 0;

  if (t == q) return 1000;

  if (t.startsWith(q)) return 500 + (100 - t.length.clamp(0, 100));

  final words = t.split(RegExp(r'\s+'));
  for (final word in words) {
    if (word.startsWith(q)) return 350 + (50 - word.length.clamp(0, 50));
  }

  if (t.contains(q)) return 120;

  return 0;
}

String _normalize(String s) =>
    s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

/// Trie une liste mutable selon un score numérique décroissant.
void sortByScore<T>(
  List<T> items,
  int Function(T) scoreFor, {
  int Function(T, T)? tieBreaker,
}) {
  items.sort((a, b) {
    final diff = scoreFor(b).compareTo(scoreFor(a));
    if (diff != 0) return diff;
    return tieBreaker?.call(a, b) ?? 0;
  });
}
