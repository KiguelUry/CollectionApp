import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_item_scope.dart';
import '../utils/supabase_embeds.dart';

/// Source unique de lecture `collection_items` (hub, drawer, prêts, social…).
///
/// Un seul GET réseau + `inFlight` : les compteurs / wishlists / doublons /
/// labels de lieux se dérivent en mémoire.
class InventoryService {
  final _client = Supabase.instance.client;

  /// Une lecture pour le hub et les grilles de catégorie.
  ///
  /// Colonnes explicites (pas de `*`) : tout ce que [CollectionItem.fromJson]
  /// lit, plus les jointures déjà utilisées par les listes
  /// (`locations`, `groups`, détenteur, auteur, emprunteur).
  static const hubSelect =
      'id, title, quantity, category, subcategory, is_wishlist, is_sold, '
      'is_for_sale, is_read, is_expansion, parent_game_id, added_by, group_id, '
      'location_id, location_user_id, loaned_to_id, loaned_to_name, loaned_at, '
      'image_url, metadata, games_played, purchase_price, min_players, '
      'max_players, playing_time, rating, review, condition, personal_rules, '
      'series_id, volume_id, created_at, '
      '${SupabaseEmbeds.locationsLabel}, '
      '${SupabaseEmbeds.groupsName}, '
      'location_holder:${SupabaseEmbeds.locationHolderProfile}, '
      'added_by_profile:${SupabaseEmbeds.addedByProfileUsername}, '
      'loaned_to:${SupabaseEmbeds.loanedToProfile}';

  static const _ttl = Duration(minutes: 10);

  static List<CollectionItem>? _cache;
  static List<Map<String, dynamic>>? _rawCache;
  static DateTime? _cacheAt;
  static String? _cacheUserId;
  static Future<List<CollectionItem>>? _inFlight;

  /// Invalide le cache (après vente / rendu prêt / mutation structurelle).
  static void invalidateCache() {
    _cache = null;
    _rawCache = null;
    _cacheAt = null;
    _cacheUserId = null;
    _inFlight = null;
  }

  /// Met à jour une ligne déjà en cache, sans nouveau SELECT.
  static void patchRow(String id, void Function(Map<String, dynamic> row) edit) {
    final rows = _rawCache;
    if (rows == null) return;
    for (final row in rows) {
      if (row['id']?.toString() == id) {
        edit(row);
        break;
      }
    }
    _cache = [
      for (final row in rows)
        CollectionItem.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  /// Tous les objets perso + groupes (1 requête collection_items).
  Future<List<CollectionItem>> fetchOwnedItems({bool force = false}) =>
      _fetchAll(force: force);

  /// Même lecture, en maps, pour les grilles qui filtrent par catégorie.
  Future<List<Map<String, dynamic>>> fetchRows({bool force = false}) async {
    await _fetchAll(force: force);
    return [
      for (final row in _rawCache ?? const <Map<String, dynamic>>[])
        Map<String, dynamic>.from(row),
    ];
  }

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
      final raw = <Map<String, dynamic>>[];
      final items = <CollectionItem>[];
      for (final row in rows as List) {
        try {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id']?.toString() ?? '';
          if (id.isNotEmpty && !seen.add(id)) continue;
          raw.add(map);
          items.add(CollectionItem.fromJson(map));
        } catch (_) {}
      }
      _rawCache = raw;
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
