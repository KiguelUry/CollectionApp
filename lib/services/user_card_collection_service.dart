import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/card_subcategory.dart';
import '../models/collection_category.dart';
import '../models/pokemon_card_lang.dart';
import '../models/tcg_set_info.dart';

/// Cartes déjà dans la collection (pour badges « possédé »).
class UserCardCollectionService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  static List<String> _catalogIdKeys(CardSubcategory sub) => switch (sub) {
        CardSubcategory.pokemon => ['tcgdex_id', 'pokemon_tcg_id'],
        CardSubcategory.magic => ['scryfall_id'],
        CardSubcategory.yugioh => ['ygoprodeck_id'],
        CardSubcategory.lorcana => ['lorcast_id'],
        CardSubcategory.onepiece => ['onepiece_card_id'],
        _ => ['catalog_id'],
      };

  static String? catalogIdFromMetadata(
    Map<String, dynamic>? meta,
    CardSubcategory sub,
  ) {
    if (meta == null) return null;
    if (sub == CardSubcategory.pokemon) {
      final key = PokemonCardLang.catalogKeyFromMetadata(meta);
      return key.isEmpty ? null : key;
    }
    for (final key in _catalogIdKeys(sub)) {
      final id = meta[key]?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  /// Clé catalogue pour badges possédé / wishlist dans les grilles.
  static String catalogKeyForTcgCard(
    TcgCatalogCard card,
    CardSubcategory sub,
  ) {
    if (sub == CardSubcategory.pokemon) {
      final lang = card.raw['card_lang'] ?? PokemonCardLang.fr;
      return PokemonCardLang.catalogKey(card.id, lang: lang);
    }
    return card.id;
  }

  Future<Set<String>> ownedCatalogIds(CardSubcategory sub) async {
    final userId = _userId;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('metadata')
        .eq('category', CollectionCategory.card.dbValue)
        .eq('subcategory', sub.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    final ids = <String>{};
    for (final row in rows as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      final id = catalogIdFromMetadata(meta, sub);
      if (id != null) ids.add(id);
    }
    return ids;
  }

  Future<Set<String>> wishlistCatalogIds(CardSubcategory sub) async {
    final userId = _userId;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('metadata')
        .eq('category', CollectionCategory.card.dbValue)
        .eq('subcategory', sub.dbValue)
        .eq('is_wishlist', true)
        .eq('added_by', userId);

    final ids = <String>{};
    for (final row in rows as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      final id = catalogIdFromMetadata(meta, sub);
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// Retire une carte wishlist par id catalogue.
  Future<bool> removeWishlistByCatalogId(
    CardSubcategory sub,
    String catalogId,
  ) async {
    final userId = _userId;
    if (userId == null || catalogId.isEmpty) return false;

    final rows = await _client
        .from('collection_items')
        .select('id, metadata')
        .eq('category', CollectionCategory.card.dbValue)
        .eq('subcategory', sub.dbValue)
        .eq('is_wishlist', true)
        .eq('added_by', userId);

    for (final row in rows as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      if (catalogIdFromMetadata(meta, sub) == catalogId) {
        await _client.from('collection_items').delete().eq('id', row['id']);
        return true;
      }
    }
    return false;
  }

  Future<bool> removeOwnedByCatalogId(
    CardSubcategory sub,
    String catalogId,
  ) async {
    final userId = _userId;
    if (userId == null || catalogId.isEmpty) return false;

    final rows = await _client
        .from('collection_items')
        .select('id, metadata')
        .eq('category', CollectionCategory.card.dbValue)
        .eq('subcategory', sub.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    for (final row in rows as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      if (catalogIdFromMetadata(meta, sub) == catalogId) {
        await _client.from('collection_items').delete().eq('id', row['id']);
        return true;
      }
    }
    return false;
  }

  /// Nombre de cartes possédées par set (`set_id` / `set_code`).
  Future<Map<String, int>> ownedCountsBySet(CardSubcategory sub) async {
    final userId = _userId;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('metadata')
        .eq('category', CollectionCategory.card.dbValue)
        .eq('subcategory', sub.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    final counts = <String, int>{};
    for (final row in rows as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      final setId = meta?['set_id']?.toString();
      final setCode = meta?['set_code']?.toString();
      if (setId != null && setId.isNotEmpty) {
        counts[setId] = (counts[setId] ?? 0) + 1;
      }
      if (setCode != null && setCode.isNotEmpty) {
        counts[setCode] = (counts[setCode] ?? 0) + 1;
      }
    }
    return counts;
  }

  int ownedInSet(Map<String, int> counts, TcgSetInfo set) {
    final byId = counts[set.id] ?? 0;
    final byCode = set.code != null ? (counts[set.code!] ?? 0) : 0;
    return byId > byCode ? byId : byCode;
  }

  Future<Set<String>> ownedSetCodes(CardSubcategory sub) async {
    final userId = _userId;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('metadata')
        .eq('category', CollectionCategory.card.dbValue)
        .eq('subcategory', sub.dbValue)
        .eq('is_wishlist', false)
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
