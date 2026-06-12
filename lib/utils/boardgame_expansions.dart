import '../models/collection_item.dart';

const _ownedKey = 'owned_expansion_bgg_ids';

/// Identifiants BGG des extensions possédées (stockés dans `metadata`).
List<String> ownedExpansionBggIds(Map<String, dynamic>? metadata) {
  final raw = metadata?[_ownedKey];
  if (raw is! List) return const [];
  return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
}

int ownedExpansionCount(CollectionItem item) =>
    ownedExpansionBggIds(item.metadata).length;

Map<String, dynamic> metadataWithOwnedExpansions(
  Map<String, dynamic>? metadata,
  List<String> ids,
) {
  final base = Map<String, dynamic>.from(metadata ?? {});
  base[_ownedKey] = ids;
  return base;
}
