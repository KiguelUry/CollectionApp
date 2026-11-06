import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_item_scope.dart';

/// Source unique de lecture `collection_items` (hub, drawer, prêts, social…).
///
/// Un seul GET réseau + `inFlight` : les compteurs / wishlists / doublons /
/// labels de lieux se dérivent en mémoire.
class InventoryService {
  final _client = Supabase.instance.client;

  /// Colonnes hub + metadata + label lieu (1 GET, pas de select=metadata séparé).
  static const hubSelect =
      'id, title, quantity, category, subcategory, is_wishlist, is_sold, '
      'is_for_sale, is_expansion, parent_game_id, added_by, group_id, '
      'location_id, location_user_id, loaned_to_id, loaned_to_name, loaned_at, '
      'image_url, metadata, games_played, purchase_price, min_players, '
      'max_players, playing_time, rating, series_id, volume_id, created_at, '
      'locations(label)';

  static const _ttl = Duration(minutes: 10);

  static List<CollectionItem>? _cache;
  static DateTime? _cacheAt;
  static String? _cacheUserId;
  static Future<List<CollectionItem>>? _inFlight;

  /// Invalide le cache (après vente / rendu prêt / mutation structurelle).
  static void invalidateCache() {
    _cache = null;
    _cacheAt = null;
    _cacheUserId = null;
    _inFlight = null;
  }

  /// Tous les objets perso + groupes (1 requête collection_items).
  Future<List<CollectionItem>> fetchOwnedItems({bool force = false}) =>
      _fetchAll(force: force);

  Future<List<CollectionItem>> _fetchAll({bool force = false}) async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return [];

    final now = DateTime.now();
    if (!force &&
        _cache != null &&
        _cacheUserId == userId &&
        _cacheAt != null &&
        now.difference(_cacheAt!) < _ttl) {
      return _cache!;
    }
    // Déduplique strictement avant la 1re réponse.
    if (!force && _inFlight != null && _cacheUserId == userId) {
      return _inFlight!;
    }

    _cacheUserId = userId;
    final future = () async {
      final groupIds = await CollectionItemScope.myGroupIds(userId);
      final filter = groupIds.isEmpty
          ? CollectionItemScope.personalOrFilter(userId)
          : '${CollectionItemScope.personalOrFilter(userId)},'
              'group_id.in.(${groupIds.join(',')})';

      final rows = await _client
          .from('collection_items')
          .select(hubSelect)
          .or(filter);

      final seen = <String>{};
      final items = <CollectionItem>[];
      for (final row in rows as List) {
        try {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id']?.toString() ?? '';
          if (id.isNotEmpty && !seen.add(id)) continue;
          items.add(CollectionItem.fromJson(map));
        } catch (_) {}
      }
      _cache = items;
      _cacheAt = DateTime.now();
      _cacheUserId = userId;
      return items;
    }();
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  /// Doublons : même titre + catégorie, ou quantité > 1 (hors wishlist / vendus).
  Future<List<GroupedCollectionItem>> fetchDuplicates() async {
    final items = (await _fetchAll())
        .where((i) => !i.isWishlist && !i.isSold)
        .toList();
    return CollectionGridGrouper.group(items)
        .where((g) => g.hasDuplicates)
        .toList();
  }

  Future<List<CollectionItem>> fetchForSale() async {
    return (await _fetchAll())
        .where((i) => i.isForSale && !i.isSold && !i.isWishlist)
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<List<CollectionItem>> fetchSold() async {
    return (await _fetchAll())
        .where((i) => i.isSold)
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<void> setForSale(String itemId, bool value) async {
    await _client.from('collection_items').update({
      'is_for_sale': value,
      if (value) 'is_sold': false,
    }).eq('id', itemId);
    invalidateCache();
  }

  Future<void> setSold(String itemId, bool value) async {
    await _client.from('collection_items').update({
      'is_sold': value,
      if (value) 'is_for_sale': false,
    }).eq('id', itemId);
    invalidateCache();
  }
}
