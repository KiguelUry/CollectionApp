import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/card_subcategory.dart';
import '../models/collection_category.dart';
import '../models/pokemon_card_lang.dart';
import '../models/tcg_set_info.dart';
import 'supabase_read_cache.dart';

/// Cartes déjà dans la collection (pour badges « possédé »).
class UserCardCollectionService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  static List<String> _catalogIdKeys(CardSubcategory sub) => switch (sub) {
        CardSubcategory.pokemon => ['tcgdex_id', 'pokemon_tcg_id'],
        CardSubcategory.magic => ['scryfall_id'],
        CardSubcategory.yugioh => ['ygoprodeck_id'],
        CardSubcategory.lorcana => ['lorcast_id'],
        CardSubcategory.riftbound => ['riftscribe_id'],
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

  /// Une seule lecture metadata par (sub, wishlist) — TTL + inFlight.
  Future<List<Map<String, dynamic>>> _cardMetaRows(
    CardSubcategory sub, {
    required bool wishlist,
  }) async {
    final userId = _userId;
    if (userId == null) return [];

    return SupabaseReadCache.getOrFetch<List<Map<String, dynamic>>>(
      key: 'card_meta:$userId:${sub.dbValue}:$wishlist',
      loader: () async {
        var query = _client
            .from('collection_items')
            .select('id, metadata')
            .eq('category', CollectionCategory.card.dbValue)
            .eq('subcategory', sub.dbValue)
            .eq('is_wishlist', wishlist);
        query = wishlist
            ? query.eq('added_by', userId)
            : query.or('added_by.eq.$userId,location_user_id.eq.$userId');
        final rows = await query;
        return [
          for (final row in rows as List)
            Map<String, dynamic>.from(row as Map),
        ];
      },
    );
  }

  void _invalidateCardMeta(CardSubcategory sub) {
    final userId = _userId;
    if (userId == null) return;
    SupabaseReadCache.invalidate('card_meta:$userId:${sub.dbValue}:');
  }

  Future<Set<String>> ownedCatalogIds(CardSubcategory sub) async {
    final rows = await _cardMetaRows(sub, wishlist: false);
    final ids = <String>{};
    for (final row in rows) {
      final id = catalogIdFromMetadata(
        row['metadata'] is Map
            ? Map<String, dynamic>.from(row['metadata'] as Map)
            : null,
        sub,
      );
      if (id != null) ids.add(id);
    }
    return ids;
  }

  Future<Set<String>> wishlistCatalogIds(CardSubcategory sub) async {
    final rows = await _cardMetaRows(sub, wishlist: true);
    final ids = <String>{};
    for (final row in rows) {
      final id = catalogIdFromMetadata(
        row['metadata'] is Map
            ? Map<String, dynamic>.from(row['metadata'] as Map)
            : null,
        sub,
      );
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// Retire une carte wishlist par id catalogue.
  Future<bool> removeWishlistByCatalogId(
    CardSubcategory sub,
    String catalogId,
  ) async {
    if (catalogId.isEmpty) return false;
    final rows = await _cardMetaRows(sub, wishlist: true);
    for (final row in rows) {
      final meta = row['metadata'] is Map
          ? Map<String, dynamic>.from(row['metadata'] as Map)
          : null;
      if (catalogIdFromMetadata(meta, sub) == catalogId) {
        await _client.from('collection_items').delete().eq('id', row['id']);
        _invalidateCardMeta(sub);
        return true;
      }
    }
    return false;
  }

  Future<bool> removeOwnedByCatalogId(
    CardSubcategory sub,
    String catalogId,
  ) async {
    if (catalogId.isEmpty) return false;
    final rows = await _cardMetaRows(sub, wishlist: false);
    for (final row in rows) {
      final meta = row['metadata'] is Map
          ? Map<String, dynamic>.from(row['metadata'] as Map)
          : null;
      if (catalogIdFromMetadata(meta, sub) == catalogId) {
        await _client.from('collection_items').delete().eq('id', row['id']);
        _invalidateCardMeta(sub);
        return true;
      }
    }
    return false;
  }

  /// Nombre de cartes possédées par set (`set_id` / `set_code`).
  Future<Map<String, int>> ownedCountsBySet(CardSubcategory sub) async {
    final rows = await _cardMetaRows(sub, wishlist: false);
    final counts = <String, int>{};
    for (final row in rows) {
      final meta = row['metadata'];
      if (meta is! Map) continue;
      final setId = meta['set_id']?.toString();
      final setCode = meta['set_code']?.toString();
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
    final rows = await _cardMetaRows(sub, wishlist: false);
    final codes = <String>{};
    for (final row in rows) {
      final meta = row['metadata'];
      if (meta is! Map) continue;
      final setId = meta['set_id']?.toString();
      final setCode = meta['set_code']?.toString();
      if (setId != null && setId.isNotEmpty) codes.add(setId);
      if (setCode != null && setCode.isNotEmpty) codes.add(setCode);
    }
    return codes;
  }
}
