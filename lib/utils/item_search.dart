import '../models/collection_item.dart';

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
};

/// Minuscules, sans accents ni ponctuation (« Esquissé ! » → « esquisse »).
String normalizeSearchText(String raw) {
  final lower = raw.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_accents[ch] ?? ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r"[^a-z0-9]+"), ' ')
      .trim();
}

/// Titre d'origine (BGG) conservé quand l'utilisateur renomme un jeu.
String? originalTitleOf(CollectionItem item) {
  final raw = item.metadata?['original_title']?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  if (raw.toLowerCase() == item.title.trim().toLowerCase()) return null;
  return raw;
}

/// Vrai si [query] correspond au titre affiché OU au titre BGG d'origine.
bool itemMatchesSearch(CollectionItem item, String query) {
  final q = normalizeSearchText(query);
  if (q.isEmpty) return true;
  if (normalizeSearchText(item.title).contains(q)) return true;
  final orig = originalTitleOf(item);
  return orig != null && normalizeSearchText(orig).contains(q);
}
