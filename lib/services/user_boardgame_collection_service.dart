import 'package:supabase_flutter/supabase_flutter.dart';

import '../catalog/services/user_catalog_service.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import 'boardgame_expansion_service.dart';
import 'inventory_service.dart';

/// Jeux déjà possédés / en wishlist (clé catalogue = `bgg_id` ou titre).
///
/// Lectures : uniquement [InventoryService] (0 SQL supplémentaire si le hub
/// a déjà chargé la collection).
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

  Future<List<CollectionItem>> _boardgames() async {
    final items = await InventoryService().fetchOwnedItems();
    return [
      for (final item in items)
        if (item.category == CollectionCategory.boardgame) item,
    ];
  }

  @override
  Future<Set<String>> ownedCatalogKeys() async {
    final userId = _userId;
    if (userId == null) return {};

    final keys = <String>{};
    for (final item in await _boardgames()) {
      if (item.isWishlist || item.isSold) continue;
      final meta = item.metadata;
      final parentId = item.parentGameId;
      final isExpansion = item.isExpansion;

      if (isExpansion && parentId != null && parentId.isNotEmpty) {
        final id = meta?['bgg_id']?.toString();
        if (id != null && id.isNotEmpty) keys.add(id);
        continue;
      }

      keys.add(catalogKeyFromMetadata(meta, item.title));
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

    final keys = <String>{};
    for (final item in await _boardgames()) {
      if (!item.isWishlist) continue;
      if (item.addedBy != null && item.addedBy != userId) continue;
      keys.add(catalogKeyFromMetadata(item.metadata, item.title));
    }
    return keys;
  }

  @override
  Future<bool> removeWishlistByCatalogKey(String catalogKey) async {
    final userId = _userId;
    if (userId == null || catalogKey.isEmpty) return false;

    for (final item in await _boardgames()) {
      if (!item.isWishlist) continue;
      if (item.addedBy != null && item.addedBy != userId) continue;
      if (catalogKeyFromMetadata(item.metadata, item.title) != catalogKey) {
        continue;
      }
      await _client.from('collection_items').delete().eq('id', item.id);
      InventoryService.invalidateCache();
      return true;
    }
    return false;
  }

  @override
  Future<bool> removeOwnedByCatalogKey(String catalogKey) async {
    final userId = _userId;
    if (userId == null || catalogKey.isEmpty) return false;

    final items = await _boardgames();
    for (final item in items) {
      if (item.isWishlist) continue;
      final meta = item.metadata;
      if (catalogKeyFromMetadata(meta, item.title) == catalogKey) {
        await _client.from('collection_items').delete().eq('id', item.id);
        InventoryService.invalidateCache();
        return true;
      }
      if (meta?['bgg_id']?.toString() == catalogKey &&
          item.parentGameId != null) {
        final parentId = item.parentGameId!;
        CollectionItem? parent;
        for (final candidate in items) {
          if (candidate.id == parentId) {
            parent = candidate;
            break;
          }
        }
        if (parent == null) {
          final parentRow = await _client
              .from('collection_items')
              .select(InventoryService.hubSelect)
              .eq('id', parentId)
              .maybeSingle();
          if (parentRow != null) {
            parent = CollectionItem.fromJson(
              Map<String, dynamic>.from(parentRow),
            );
          }
        }
        if (parent != null) {
          await BoardgameExpansionService().unlinkExpansionFromBase(
            base: parent,
            expansionBggId: catalogKey,
          );
          InventoryService.invalidateCache();
          return true;
        }
      }
    }
    return false;
  }
}
