import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';

/// Jeux déjà possédés / en wishlist (clé catalogue = `bgg_id` ou titre).
class UserBoardgameCollectionService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  static String catalogKeyFromMetadata(Map<String, dynamic>? meta, String title) {
    final id = meta?['bgg_id']?.toString().trim() ?? '';
    if (id.isNotEmpty) return id;
    return 'title:${title.trim().toLowerCase()}';
  }

  static String catalogKeyForGame(String bggId, String title) =>
      bggId.isNotEmpty ? bggId : 'title:${title.trim().toLowerCase()}';

  Future<Set<String>> ownedCatalogKeys() async {
    final userId = _userId;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('title, metadata')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    final keys = <String>{};
    for (final row in rows as List) {
      final title = row['title'] as String? ?? '';
      final meta = row['metadata'] as Map<String, dynamic>?;
      keys.add(catalogKeyFromMetadata(meta, title));
    }
    return keys;
  }

  Future<Set<String>> wishlistCatalogKeys() async {
    final userId = _userId;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('title, metadata')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', true)
        .eq('added_by', userId);

    final keys = <String>{};
    for (final row in rows as List) {
      final title = row['title'] as String? ?? '';
      final meta = row['metadata'] as Map<String, dynamic>?;
      keys.add(catalogKeyFromMetadata(meta, title));
    }
    return keys;
  }

  Future<bool> removeWishlistByCatalogKey(String catalogKey) async {
    final userId = _userId;
    if (userId == null || catalogKey.isEmpty) return false;

    final rows = await _client
        .from('collection_items')
        .select('id, title, metadata')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', true)
        .eq('added_by', userId);

    for (final row in rows as List) {
      final title = row['title'] as String? ?? '';
      final meta = row['metadata'] as Map<String, dynamic>?;
      if (catalogKeyFromMetadata(meta, title) == catalogKey) {
        await _client.from('collection_items').delete().eq('id', row['id']);
        return true;
      }
    }
    return false;
  }

  Future<bool> removeOwnedByCatalogKey(String catalogKey) async {
    final userId = _userId;
    if (userId == null || catalogKey.isEmpty) return false;

    final rows = await _client
        .from('collection_items')
        .select('id, title, metadata')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    for (final row in rows as List) {
      final title = row['title'] as String? ?? '';
      final meta = row['metadata'] as Map<String, dynamic>?;
      if (catalogKeyFromMetadata(meta, title) == catalogKey) {
        await _client.from('collection_items').delete().eq('id', row['id']);
        return true;
      }
    }
    return false;
  }
}
