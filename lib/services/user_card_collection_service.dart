import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/card_subcategory.dart';
import '../models/collection_category.dart';

/// Cartes déjà dans la collection (pour badges « possédé »).
class UserCardCollectionService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<Set<String>> ownedCatalogIds(CardSubcategory sub) async {
    final userId = _userId;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('metadata')
        .eq('category', CollectionCategory.card.dbValue)
        .eq('subcategory', sub.dbValue)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    final ids = <String>{};
    final keys = switch (sub) {
      CardSubcategory.pokemon => ['tcgdex_id', 'pokemon_tcg_id'],
      CardSubcategory.magic => ['scryfall_id'],
      CardSubcategory.yugioh => ['ygoprodeck_id'],
      CardSubcategory.lorcana => ['lorcast_id'],
      CardSubcategory.onepiece => ['onepiece_card_id'],
      _ => ['catalog_id'],
    };

    for (final row in rows as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      if (meta == null) continue;
      for (final key in keys) {
        final id = meta[key]?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  Future<Set<String>> ownedSetCodes(CardSubcategory sub) async {
    final userId = _userId;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('metadata')
        .eq('category', CollectionCategory.card.dbValue)
        .eq('subcategory', sub.dbValue)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    final codes = <String>{};
    for (final row in rows as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      final setId = meta?['set_id']?.toString();
      final setCode = meta?['set_code']?.toString();
      if (setId != null && setId.isNotEmpty) codes.add(setId);
      if (setCode != null && setCode.isNotEmpty) codes.add(setCode);
    }
    return codes;
  }
}
