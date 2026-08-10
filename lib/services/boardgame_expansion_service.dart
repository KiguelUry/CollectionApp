import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/collection_refresh.dart';
import '../utils/boardgame_cover.dart';
import '../utils/boardgame_expansions.dart';
import '../utils/whereabouts_apply.dart';

/// Gestion extensions BGG via `is_expansion` + `parent_game_id`.
class BoardgameExpansionService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  /// Masqué de la collection globale si extension liée à un parent.
  static bool isHiddenInGlobalList(CollectionItem item) {
    if (item.category != CollectionCategory.boardgame) return false;
    final hasParent =
        item.parentGameId != null && item.parentGameId!.isNotEmpty;
    if (!hasParent) return false;
    return item.isExpansion || item.metadata?['bgg_is_expansion'] == true;
  }

  static String? orphanExpansionLabel(CollectionItem item) {
    if (!item.isExpansion || item.parentGameId != null) return null;
    final title = item.parentGameTitle;
    if (title != null && title.isNotEmpty) return title;
    return item.metadata?['expansion_of_title']?.toString();
  }

  Future<CollectionItem?> findBaseByBggId(String bggId) async {
    if (bggId.isEmpty) return null;
    final userId = _userId;
    if (userId == null) return null;

    final rows = await _client
        .from('collection_items')
        .select()
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false)
        .eq('is_expansion', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    for (final row in rows as List) {
      final item = CollectionItem.fromJson(row as Map<String, dynamic>);
      if (item.metadata?['bgg_id']?.toString() == bggId) return item;
    }
    return null;
  }

  Future<CollectionItem?> findExpansionByBggId(String expansionBggId) async {
    if (expansionBggId.isEmpty) return null;
    final userId = _userId;
    if (userId == null) return null;

    final rows = await _client
        .from('collection_items')
        .select()
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    CollectionItem? fallback;
    for (final row in rows as List) {
      final item = CollectionItem.fromJson(row as Map<String, dynamic>);
      if (item.metadata?['bgg_id']?.toString() != expansionBggId) continue;
      if (item.isExpansion) return item;
      fallback ??= item;
    }
    return fallback;
  }

  /// Extension liée à un parent (enfant) — jamais parent d'autres extensions.
  static bool itemActsAsExpansion(CollectionItem item) {
    if (item.parentGameId != null && item.parentGameId!.isNotEmpty) return true;
    if (item.isExpansion) return true;
    if (item.metadata?['bgg_is_expansion'] == true) return true;
    final bggId = item.metadata?['bgg_id']?.toString();
    final baseBggId =
        item.metadata?['base_game_bgg_id']?.toString() ??
        item.metadata?['expansion_of_bgg_id']?.toString();
    if (baseBggId != null && baseBggId.isNotEmpty && baseBggId != bggId) {
      return true;
    }
    return false;
  }

  /// Jeu de base — parent possible, jamais enfant d'une extension.
  static bool itemActsAsBase(CollectionItem item) => !itemActsAsExpansion(item);

  /// Résout le couple parent/enfant (base = parent, expansion = enfant).
  static ({CollectionItem base, CollectionItem expansion}) resolveLinkPair(
    CollectionItem a,
    CollectionItem b,
  ) {
    final aExp = itemActsAsExpansion(a);
    final bExp = itemActsAsExpansion(b);
    if (aExp && !bExp) return (base: b, expansion: a);
    if (bExp && !aExp) return (base: a, expansion: b);

    final aBgg = a.metadata?['bgg_id']?.toString();
    final bBgg = b.metadata?['bgg_id']?.toString();
    final aBaseRef = a.metadata?['base_game_bgg_id']?.toString();
    final bBaseRef = b.metadata?['base_game_bgg_id']?.toString();
    if (aBaseRef != null && aBaseRef == bBgg) return (base: b, expansion: a);
    if (bBaseRef != null && bBaseRef == aBgg) return (base: a, expansion: b);

    if (a.parentGameId == b.id) return (base: b, expansion: a);
    if (b.parentGameId == a.id) return (base: a, expansion: b);

    return (base: a, expansion: b);
  }

  /// Lie une ligne extension existante au jeu de base (réconciliation).
  Future<void> linkExistingItemToBase({
    required CollectionItem base,
    required CollectionItem expansion,
  }) async {
    final pair = resolveLinkPair(base, expansion);
    final resolvedBase = pair.base;
    final resolvedExpansion = pair.expansion;

    if (resolvedBase.id == resolvedExpansion.id) return;
    if (itemActsAsExpansion(resolvedBase)) return;

    await _client
        .from('collection_items')
        .update({'is_expansion': false, 'parent_game_id': null})
        .eq('id', resolvedBase.id);

    await _client
        .from('collection_items')
        .update({'is_expansion': true, 'parent_game_id': resolvedBase.id})
        .eq('id', resolvedExpansion.id);

    final expBggId = resolvedExpansion.metadata?['bgg_id']?.toString();
    if (expBggId != null && expBggId.isNotEmpty) {
      await syncLegacyOwnedIds(resolvedBase);
    }
    CollectionRefresh.instance.bump();
  }

  /// Metadata legacy uniquement (pas de ligne enfant).
  Future<void> attachExpansionMetadataOnly({
    required CollectionItem base,
    required String expansionBggId,
  }) async {
    final owned = ownedExpansionBggIds(base.metadata).toSet()
      ..add(expansionBggId);
    final meta = metadataWithOwnedExpansions(base.metadata, owned.toList());
    await _client
        .from('collection_items')
        .update({'metadata': meta})
        .eq('id', base.id);
    CollectionRefresh.instance.bump();
  }

  Future<CollectionItem?> findBaseByItemId(String parentGameId) async {
    final row = await _client
        .from('collection_items')
        .select()
        .eq('id', parentGameId)
        .maybeSingle();
    if (row == null) return null;
    return CollectionItem.fromJson(Map<String, dynamic>.from(row));
  }

  /// IDs BGG des extensions liées (enfants + legacy metadata).
  Future<Set<String>> ownedExpansionBggIdsForBase(CollectionItem base) async {
    final baseBggId = base.metadata?['bgg_id']?.toString();
    final owned = ownedExpansionBggIds(base.metadata).toSet();
    if (baseBggId != null && baseBggId.isNotEmpty) {
      owned.remove(baseBggId);
    }

    final children = await _client
        .from('collection_items')
        .select('metadata')
        .eq('parent_game_id', base.id)
        .eq('is_expansion', true);

    for (final row in children as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      final id = meta?['bgg_id']?.toString();
      if (id == null || id.isEmpty) continue;
      if (baseBggId != null && id == baseBggId) continue;
      owned.add(id);
    }
    return owned;
  }

  Future<void> syncLegacyOwnedIds(CollectionItem base) async {
    final owned = await ownedExpansionBggIdsForBase(base);
    final meta = metadataWithOwnedExpansions(base.metadata, owned.toList());
    await _client
        .from('collection_items')
        .update({'metadata': meta})
        .eq('id', base.id);
  }

  /// Lie une extension existante ou en crée une nouvelle sous le jeu de base.
  Future<CollectionItem> linkExpansionToBase({
    required CollectionItem base,
    required String expansionBggId,
    required String title,
    Map<String, dynamic>? bggDetails,
    String? imageUrl,
    int? minPlayers,
    int? maxPlayers,
    int? playingTime,
  }) async {
    final userId = _userId;
    if (userId == null) throw StateError('Non connecté');

    if (base.isExpansion || itemActsAsExpansion(base)) {
      throw StateError('Le parent ne peut pas être une extension');
    }

    await _client
        .from('collection_items')
        .update({'is_expansion': false, 'parent_game_id': null})
        .eq('id', base.id);

    final existingChild = await _findChildByBggId(base.id, expansionBggId);
    if (existingChild != null) {
      if (existingChild.parentGameId == base.id) return existingChild;
      final meta = _expansionMeta(bggId: expansionBggId, details: bggDetails);
      await _client
          .from('collection_items')
          .update({
            'is_expansion': true,
            'parent_game_id': base.id,
            ..._inheritedWhereaboutsFields(base, meta),
          })
          .eq('id', existingChild.id);
      CollectionRefresh.instance.bump();
      return existingChild.copyWith(
        isExpansion: true,
        parentGameId: base.id,
        locationUserId: base.locationUserId,
        locationId: base.locationId,
        groupId: base.groupId,
      );
    }

    final meta = _expansionMeta(bggId: expansionBggId, details: bggDetails);

    final inserted = await _client
        .from('collection_items')
        .insert({
          'title': title.trim(),
          'category': CollectionCategory.boardgame.dbValue,
          'image_url': boardgameStorageImageUrl(
            details: bggDetails,
            catalogUrl: imageUrl,
          ),
          'is_wishlist': false,
          'quantity': 1,
          'added_by': userId,
          'is_expansion': true,
          'parent_game_id': base.id,
          'min_players': minPlayers,
          'max_players': maxPlayers,
          'playing_time': playingTime,
          ..._inheritedWhereaboutsFields(base, meta),
        })
        .select()
        .single();

    await syncLegacyOwnedIds(base);
    CollectionRefresh.instance.bump();
    return CollectionItem.fromJson(Map<String, dynamic>.from(inserted));
  }

  Future<void> unlinkExpansionFromBase({
    required CollectionItem base,
    required String expansionBggId,
  }) async {
    final child = await _findChildByBggId(base.id, expansionBggId);
    if (child != null) {
      await _client.from('collection_items').delete().eq('id', child.id);
    }

    final legacy = ownedExpansionBggIds(base.metadata).toSet()
      ..remove(expansionBggId);
    final meta = metadataWithOwnedExpansions(base.metadata, legacy.toList());
    await _client
        .from('collection_items')
        .update({'metadata': meta})
        .eq('id', base.id);
    CollectionRefresh.instance.bump();
  }

  /// Extension orpheline visible globalement (sans parent).
  Future<CollectionItem> insertOrphanExpansion({
    required String title,
    required String expansionBggId,
    required String baseBggId,
    required String? baseTitle,
    Map<String, dynamic>? bggDetails,
    String? imageUrl,
    int quantity = 1,
    String? locationId,
    String? groupId,
    int? minPlayers,
    int? maxPlayers,
    int? playingTime,
  }) async {
    final userId = _userId;
    if (userId == null) throw StateError('Non connecté');

    final meta = {
      ..._expansionMeta(bggId: expansionBggId, details: bggDetails),
      'expansion_of_bgg_id': baseBggId,
      if (baseTitle != null && baseTitle.isNotEmpty)
        'expansion_of_title': baseTitle,
      'base_game_bgg_id': baseBggId,
      'base_game_title': ?baseTitle,
    };

    final inserted = await _client
        .from('collection_items')
        .insert({
          'title': title.trim(),
          'category': CollectionCategory.boardgame.dbValue,
          'metadata': meta,
          'image_url': boardgameStorageImageUrl(
            details: bggDetails,
            catalogUrl: imageUrl,
          ),
          'is_wishlist': false,
          'quantity': quantity,
          'location_id': locationId,
          'group_id': groupId,
          'added_by': userId,
          'location_user_id': userId,
          'is_expansion': true,
          'parent_game_id': null,
          'min_players': minPlayers,
          'max_players': maxPlayers,
          'playing_time': playingTime,
        })
        .select()
        .single();

    CollectionRefresh.instance.bump();
    return CollectionItem.fromJson(Map<String, dynamic>.from(inserted));
  }

  /// Rattache une extension orpheline au jeu de base (crée la base si besoin).
  Future<CollectionItem> promoteOrphanToBase({
    required CollectionItem orphan,
  }) async {
    final baseBggId =
        orphan.metadata?['expansion_of_bgg_id']?.toString() ??
        orphan.metadata?['base_game_bgg_id']?.toString();
    if (baseBggId == null || baseBggId.isEmpty) {
      throw StateError('Extension sans jeu de base BGG');
    }

    var base = await findBaseByBggId(baseBggId);
    base ??= await _createBaseFromBgg(baseBggId, orphan);

    final expBggId = orphan.metadata?['bgg_id']?.toString() ?? '';
    await _client
        .from('collection_items')
        .update({'is_expansion': true, 'parent_game_id': base.id})
        .eq('id', orphan.id);

    if (expBggId.isNotEmpty) {
      await syncLegacyOwnedIds(base);
    }

    CollectionRefresh.instance.bump();
    return base;
  }

  Future<CollectionItem?> _findChildByBggId(
    String parentId,
    String expansionBggId,
  ) async {
    final rows = await _client
        .from('collection_items')
        .select()
        .eq('parent_game_id', parentId)
        .eq('is_expansion', true);

    for (final row in rows as List) {
      final item = CollectionItem.fromJson(row as Map<String, dynamic>);
      if (item.metadata?['bgg_id']?.toString() == expansionBggId) {
        return item;
      }
    }

    final userId = _userId;
    if (userId == null) return null;
    final standalone = await _client
        .from('collection_items')
        .select()
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    for (final row in standalone as List) {
      final item = CollectionItem.fromJson(row as Map<String, dynamic>);
      if (item.metadata?['bgg_id']?.toString() != expansionBggId) continue;
      if (item.id == parentId) continue;
      return item;
    }
    return null;
  }

  Future<CollectionItem> _createBaseFromBgg(
    String baseBggId,
    CollectionItem orphanHint,
  ) async {
    final userId = _userId!;
    final details = await BggService.getGameFullDetails(baseBggId);
    final title =
        orphanHint.parentGameTitle ??
        details?['base_game_title']?.toString() ??
        orphanHint.metadata?['expansion_of_title']?.toString() ??
        'Jeu de base';

    final meta = <String, dynamic>{'bgg_id': baseBggId};
    if (details != null) {
      for (final key in [
        'year_published',
        'min_age',
        'bgg_categories',
        'bgg_short_description',
        'bgg_avg_rating',
        'bgg_best_players',
        'bgg_gallery_urls',
      ]) {
        final v = details[key];
        if (v != null) meta[key] = v;
      }
    }

    final inserted = await _client
        .from('collection_items')
        .insert({
          'title': title,
          'category': CollectionCategory.boardgame.dbValue,
          'metadata': meta,
          'image_url': boardgameStorageImageUrl(details: details),
          'is_wishlist': false,
          'quantity': 1,
          'added_by': userId,
          'location_user_id': userId,
          'is_expansion': false,
          'parent_game_id': null,
          'min_players': details?['min_players'],
          'max_players': details?['max_players'],
          'playing_time': details?['playing_time'],
        })
        .select()
        .single();

    return CollectionItem.fromJson(Map<String, dynamic>.from(inserted));
  }

  Map<String, dynamic> _expansionMeta({
    required String bggId,
    Map<String, dynamic>? details,
  }) {
    final meta = <String, dynamic>{'bgg_id': bggId, 'bgg_is_expansion': true};
    if (details != null) {
      for (final key in [
        'year_published',
        'min_age',
        'bgg_categories',
        'base_game_bgg_id',
        'base_game_title',
        'bgg_short_description',
        'bgg_avg_rating',
        'bgg_best_players',
        'bgg_gallery_urls',
      ]) {
        final v = details[key];
        if (v != null) meta[key] = v;
      }
    }
    return meta;
  }

  Map<String, dynamic> _inheritedWhereaboutsFields(
    CollectionItem base,
    Map<String, dynamic> expansionMeta,
  ) {
    final draft = base.copyWith(metadata: expansionMeta);
    if (base.locationUserId != null && base.locationUserId!.isNotEmpty) {
      return {
        'location_user_id': base.locationUserId,
        'location_id': base.locationId,
        'group_id': base.groupId,
        'metadata': whereaboutsMetadataForSave(draft),
      };
    }
    final meta = Map<String, dynamic>.from(expansionMeta);
    final holder = base.metadata?['holder_label']?.toString().trim();
    if (holder != null && holder.isNotEmpty) {
      meta['holder_label'] = holder;
    }
    final withHolder = draft.copyWith(
      metadata: meta,
      clearLocationUserId: base.locationUserId == null,
      locationUserId: null,
    );
    return {
      'location_user_id': null,
      'location_id': base.locationId,
      'group_id': base.groupId,
      'metadata': whereaboutsMetadataForSave(withHolder),
    };
  }
}
