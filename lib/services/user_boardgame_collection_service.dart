import 'package:supabase_flutter/supabase_flutter.dart';

import '../catalog/services/user_catalog_service.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import 'boardgame_expansion_service.dart';

/// Jeux déjà possédés / en wishlist (clé catalogue = `bgg_id` ou titre).
class UserBoardgameCollectionService implements UserCatalogService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  static String catalogKeyFromMetadata(Map<String, dynamic>? meta, String title) {
    final id = meta?['bgg_id']?.toString().trim() ?? '';
    if (id.isNotEmpty) return id;
    return 'title:${title.trim().toLowerCase()}';
  }

  static String catalogKeyForGame(String bggId, String title) =>
      bggId.isNotEmpty ? bggId : 'title:${title.trim().toLowerCase()}';

  @override
  Future<Set<String>> ownedCatalogKeys() async {
    final userId = _userId;
    if (userId == null) return {};

    final rows = await _client
        .from('collection_items')
        .select('title, metadata, parent_game_id, is_expansion')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    final keys = <String>{};
    for (final row in rows as List) {
      final title = row['title'] as String? ?? '';
      final meta = row['metadata'] as Map<String, dynamic>?;
      final parentId = row['parent_game_id'] as String?;
      final isExpansion = row['is_expansion'] as bool? ?? false;

      if (isExpansion && parentId != null && parentId.isNotEmpty) {
        final id = meta?['bgg_id']?.toString();
        if (id != null && id.isNotEmpty) keys.add(id);
        continue;
      }

      keys.add(catalogKeyFromMetadata(meta, title));
      final ownedExp = meta?['owned_expansion_bgg_ids'];
      if (ownedExp is List) {
        for (final id in ownedExp) {
          final s = id.toString();
          if (s.isNotEmpty) keys.add(s);
        }
      }
    }
    return keys;
  }

  @override
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

  @override
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

  @override
  Future<bool> removeOwnedByCatalogKey(String catalogKey) async {
    final userId = _userId;
    if (userId == null || catalogKey.isEmpty) return false;

    final rows = await _client
        .from('collection_items')
        .select('id, title, metadata, parent_game_id, is_expansion')
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
      if (meta?['bgg_id']?.toString() == catalogKey &&
          row['parent_game_id'] != null) {
        final parentId = row['parent_game_id'] as String;
        final parentRow = await _client
            .from('collection_items')
            .select()
            .eq('id', parentId)
            .maybeSingle();
        if (parentRow != null) {
          final parent = CollectionItem.fromJson(
            Map<String, dynamic>.from(parentRow),
          );
          await BoardgameExpansionService().unlinkExpansionFromBase(
            base: parent,
            expansionBggId: catalogKey,
          );
          return true;
        }
      }
    }
    return false;
  }
}
