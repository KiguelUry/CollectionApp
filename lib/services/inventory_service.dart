import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_item_scope.dart';
import '../utils/supabase_embeds.dart';

class InventoryService {
  final _client = Supabase.instance.client;

  static const _select = SupabaseEmbeds.collectionItem;
  static const _ttl = Duration(minutes: 5);

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

  /// Tous les objets dont je suis propriétaire ou détenteur (groupes inclus).
  /// Cache mémoire 5 min + dédoublonnage in-flight (onglets Accueil / Prêts…).
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
    if (!force && _inFlight != null && _cacheUserId == userId) {
      return _inFlight!;
    }

    final future = () async {
      final rows = await CollectionItemScope.ownedByUser(
        _client.from('collection_items').select(_select),
        userId: userId,
      );
      final items = (rows as List)
          .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
          .toList();
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
