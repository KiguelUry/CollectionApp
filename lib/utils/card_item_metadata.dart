import '../models/card_subcategory.dart';
import '../models/collection_item.dart';

/// Métadonnées cartes pour filtres (rareté, type Pokémon…).
String? cardRarityFromMetadata(Map<String, dynamic>? metadata) {
  if (metadata == null) return null;
  final r = metadata['rarity']?.toString().trim();
  return r != null && r.isNotEmpty ? r : null;
}

List<String> pokemonTypesFromMetadata(Map<String, dynamic>? metadata) {
  if (metadata == null) return const [];
  final raw = metadata['types'];
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  final s = raw?.toString().trim();
  if (s == null || s.isEmpty) return const [];
  return s.split(RegExp(r'[,/|]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

Set<String> distinctCardRarities(Iterable<CollectionItem> items) {
  final out = <String>{};
  for (final item in items) {
    final r = cardRarityFromMetadata(item.metadata);
    if (r != null) out.add(r);
  }
  return out;
}

Set<String> distinctPokemonTypes(Iterable<CollectionItem> items) {
  final out = <String>{};
  for (final item in items) {
    out.addAll(pokemonTypesFromMetadata(item.metadata));
  }
  return out;
}

List<CardSubcategory> distinctCardSubcategories(Iterable<CollectionItem> items) {
  final seen = <String>{};
  final out = <CardSubcategory>[];
  for (final item in items) {
    final sub = item.subcategory;
    if (sub == null || sub.isEmpty || !seen.add(sub)) continue;
    out.add(CardSubcategory.fromDbValue(sub));
  }
  out.sort((a, b) {
    if (a == CardSubcategory.other) return 1;
    if (b == CardSubcategory.other) return -1;
    return a.label.compareTo(b.label);
  });
  return out;
}
