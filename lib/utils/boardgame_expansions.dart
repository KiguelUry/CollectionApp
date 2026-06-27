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

/// Compte les extensions possédées sans double-compter metadata + lignes enfant.
int countUniqueOwnedExpansions(Iterable<Map<String, dynamic>> boardgameRows) {
  final ids = <String>{};
  for (final row in boardgameRows) {
    final isExpansion = row['is_expansion'] as bool? ?? false;
    final meta = row['metadata'] as Map<String, dynamic>?;
    if (isExpansion) {
      final id = meta?['bgg_id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    } else {
      ids.addAll(ownedExpansionBggIds(meta));
    }
  }
  return ids.length;
}

Map<String, dynamic> metadataWithOwnedExpansions(
  Map<String, dynamic>? metadata,
  List<String> ids,
) {
  final base = Map<String, dynamic>.from(metadata ?? {});
  base[_ownedKey] = ids;
  return base;
}
