import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/boardgame_expansion_service.dart';
import '../services/collection_refresh.dart';
import 'boardgame_expansion_flow.dart';
import 'boardgame_expansions.dart';

/// Résultat d'une passe de réparation + réconciliation extensions BGG.
class BoardgameExpansionReconcileResult {
  final int repairedCount;
  final int metadataFixedCount;
  final int mergedCount;
  final int deletedCount;

  const BoardgameExpansionReconcileResult({
    this.repairedCount = 0,
    this.metadataFixedCount = 0,
    this.mergedCount = 0,
    this.deletedCount = 0,
  });

  bool get changed =>
      repairedCount > 0 ||
      metadataFixedCount > 0 ||
      mergedCount > 0 ||
      deletedCount > 0;

  int get totalFixed => repairedCount + metadataFixedCount + mergedCount;
}

Future<List<CollectionItem>> _loadUserBoardgames() async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final rows = await client
      .from('collection_items')
      .select()
      .eq('category', CollectionCategory.boardgame.dbValue)
      .eq('is_wishlist', false)
      .or('added_by.eq.$userId,location_user_id.eq.$userId');

  return (rows as List)
      .map((r) => CollectionItem.fromJson(r as Map<String, dynamic>))
      .toList();
}

bool _looksLikeExpansion(CollectionItem item) =>
    BoardgameExpansionService.itemActsAsExpansion(item);

String? _itemBggId(CollectionItem item) {
  final id = item.metadata?['bgg_id']?.toString();
  return (id != null && id.isNotEmpty) ? id : null;
}

String? _baseBggId(CollectionItem item) {
  final id = item.metadata?['base_game_bgg_id']?.toString() ??
      item.metadata?['expansion_of_bgg_id']?.toString();
  return (id != null && id.isNotEmpty) ? id : null;
}

Future<bool> _normalizeAsBase(SupabaseClient client, CollectionItem item) async {
  if (!_looksLikeExpansion(item) &&
      !item.isExpansion &&
      item.parentGameId == null) {
    return false;
  }
  if (!_looksLikeExpansion(item)) {
    await client.from('collection_items').update({
      'is_expansion': false,
      'parent_game_id': null,
    }).eq('id', item.id);
    return true;
  }
  return false;
}

Future<bool> _refreshExpansionMetadataFromBgg(
  SupabaseClient client,
  CollectionItem item,
) async {
  final bggId = _itemBggId(item);
  if (bggId == null) return false;

  final details = await BggService.getGameFullDetails(bggId);
  if (details == null) return false;

  final link = boardgameExpansionLinkFromDetails(details);
  final meta = Map<String, dynamic>.from(item.metadata ?? {});
  var changed = false;

  if (link.isExpansion) {
    if (meta['bgg_is_expansion'] != true) {
      meta['bgg_is_expansion'] = true;
      changed = true;
    }
    if (link.baseBggId != null && meta['base_game_bgg_id'] != link.baseBggId) {
      meta['base_game_bgg_id'] = link.baseBggId;
      changed = true;
    }
    if (link.baseTitle != null &&
        link.baseTitle!.isNotEmpty &&
        meta['base_game_title'] != link.baseTitle) {
      meta['base_game_title'] = link.baseTitle;
      changed = true;
    }
    if (!item.isExpansion) {
      await client
          .from('collection_items')
          .update({'is_expansion': true})
          .eq('id', item.id);
      changed = true;
    }
  } else {
    for (final key in [
      'bgg_is_expansion',
      'base_game_bgg_id',
      'base_game_title',
      'expansion_of_bgg_id',
      'expansion_of_title',
    ]) {
      if (meta.remove(key) != null) changed = true;
    }
    if (item.isExpansion || item.parentGameId != null) {
      await client.from('collection_items').update({
        'is_expansion': false,
        'parent_game_id': null,
      }).eq('id', item.id);
      changed = true;
    }
  }

  if (changed) {
    await client
        .from('collection_items')
        .update({'metadata': meta})
        .eq('id', item.id);
  }
  return changed;
}

/// Réparation automatique des liens inversés / metadata BGG erronée, puis rattachement.
Future<BoardgameExpansionReconcileResult> repairAndReconcileBoardgameExpansions({
  int maxBggLookups = 24,
}) async {
  final client = Supabase.instance.client;
  if (client.auth.currentUser?.id == null) {
    return const BoardgameExpansionReconcileResult();
  }

  var metadataFixed = 0;
  var repaired = 0;
  var bggLookups = 0;

  var items = await _loadUserBoardgames();
  if (items.isEmpty) return const BoardgameExpansionReconcileResult();

  for (final item in items) {
    if (bggLookups >= maxBggLookups) break;
    final bggId = _itemBggId(item);
    if (bggId == null) continue;
    bggLookups++;
    if (await _refreshExpansionMetadataFromBgg(client, item)) {
      metadataFixed++;
    }
  }

  if (metadataFixed > 0) {
    items = await _loadUserBoardgames();
  }

  final service = BoardgameExpansionService();
  final byId = {for (final i in items) i.id: i};
  final byBggId = <String, CollectionItem>{};
  for (final item in items) {
    final id = _itemBggId(item);
    if (id != null) byBggId[id] = item;
  }

  CollectionItem? baseForExpansion(CollectionItem expansion) {
    final baseBgg = _baseBggId(expansion);
    if (baseBgg == null) return null;
    final base = byBggId[baseBgg];
    if (base == null || base.id == expansion.id) return null;
    if (_looksLikeExpansion(base)) return null;
    return base;
  }

  Future<void> linkPair(CollectionItem base, CollectionItem expansion) async {
    if (base.id == expansion.id) return;
    await service.linkExistingItemToBase(base: base, expansion: expansion);
    repaired++;
    byId[base.id] = base.copyWith(isExpansion: false, parentGameId: null);
    byId[expansion.id] = expansion.copyWith(
      isExpansion: true,
      parentGameId: base.id,
    );
  }

  // Jeux de base marqués à tort comme extensions.
  for (final item in items) {
    if (_looksLikeExpansion(item)) continue;
    if (await _normalizeAsBase(client, item)) repaired++;
  }

  items = await _loadUserBoardgames();
  for (final item in items) {
    byId[item.id] = item;
    final bggId = _itemBggId(item);
    if (bggId != null) byBggId[bggId] = item;
  }

  for (final item in items) {
    final parentId = item.parentGameId;
    if (parentId == null || parentId.isEmpty) continue;

    final parent = byId[parentId];
    if (parent == null) {
      await client.from('collection_items').update({
        'parent_game_id': null,
      }).eq('id', item.id);
      repaired++;
      continue;
    }

    if (parent.id == item.id) {
      await client.from('collection_items').update({
        'parent_game_id': null,
      }).eq('id', item.id);
      repaired++;
      continue;
    }

    // Parent = extension, enfant = jeu de base → lien inversé.
    if (_looksLikeExpansion(parent) && !_looksLikeExpansion(item)) {
      await linkPair(item, parent);
      continue;
    }

    // Enfant = extension, parent = mauvais jeu (autre extension ou mauvais bgg).
    if (_looksLikeExpansion(item)) {
      final expectedBase = baseForExpansion(item);
      if (expectedBase != null && expectedBase.id != parent.id) {
        await linkPair(expectedBase, item);
        continue;
      }
      if (_looksLikeExpansion(parent)) {
        final base = expectedBase;
        if (base != null) await linkPair(base, item);
      }
    }

    // Jeu de base avec parent (souvent vers sa propre extension).
    if (!_looksLikeExpansion(item)) {
      if (_looksLikeExpansion(parent)) {
        await linkPair(item, parent);
      } else {
        await _normalizeAsBase(client, item);
        repaired++;
      }
    }
  }

  // Extensions sans parent mais avec base BGG connue.
  for (final item in items) {
    if (!_looksLikeExpansion(item)) continue;
    if (item.parentGameId != null && item.parentGameId!.isNotEmpty) continue;
    final base = baseForExpansion(item);
    if (base == null) continue;
    await linkPair(base, item);
  }

  final mergeResult = await reconcileBoardgameExpansions(
    maxBggLookups: (maxBggLookups - bggLookups).clamp(0, maxBggLookups),
  );

  if (repaired > 0 || metadataFixed > 0 || mergeResult.mergedCount > 0) {
    CollectionRefresh.instance.bump();
  }

  return BoardgameExpansionReconcileResult(
    repairedCount: repaired,
    metadataFixedCount: metadataFixed,
    mergedCount: mergeResult.mergedCount,
    deletedCount: mergeResult.deletedCount,
  );
}

/// Rattache les extensions en double (legacy metadata ou orphelines).
Future<BoardgameExpansionReconcileResult> reconcileBoardgameExpansions({
  int maxBggLookups = 12,
}) async {
  final items = await _loadUserBoardgames();
  if (items.isEmpty) return const BoardgameExpansionReconcileResult();

  final service = BoardgameExpansionService();
  final byBggId = <String, CollectionItem>{};
  for (final item in items) {
    final id = _itemBggId(item);
    if (id != null) byBggId[id] = item;
  }

  final linked = <String>{};
  var merged = 0;
  var bggLookups = 0;

  Future<void> linkToBase({
    required CollectionItem expansionItem,
    required CollectionItem baseItem,
    required String expansionBggId,
  }) async {
    if (linked.contains(expansionItem.id)) return;
    if (expansionItem.parentGameId == baseItem.id &&
        expansionItem.isExpansion &&
        !baseItem.isExpansion) {
      linked.add(expansionItem.id);
      return;
    }

    await service.linkExistingItemToBase(
      base: baseItem,
      expansion: expansionItem,
    );
    linked.add(expansionItem.id);
    merged++;
  }

  for (final item in items) {
    if (linked.contains(item.id)) continue;
    if (item.parentGameId != null && item.parentGameId!.isNotEmpty) continue;

    final expId = _itemBggId(item);
    if (expId == null) continue;

    for (final other in items) {
      if (other.id == item.id || linked.contains(item.id)) continue;
      if (!ownedExpansionBggIds(other.metadata).contains(expId)) continue;
      if (_looksLikeExpansion(other)) continue;
      await linkToBase(
        expansionItem: item,
        baseItem: other,
        expansionBggId: expId,
      );
      break;
    }
  }

  for (final item in items) {
    if (linked.contains(item.id)) continue;
    if (item.parentGameId != null && item.parentGameId!.isNotEmpty) continue;

    final expId = _itemBggId(item);
    if (expId == null) continue;

    final baseId = _baseBggId(item);
    if (baseId != null && baseId.isNotEmpty) {
      final base = byBggId[baseId];
      if (base != null && base.id != item.id && !_looksLikeExpansion(base)) {
        await linkToBase(
          expansionItem: item,
          baseItem: base,
          expansionBggId: expId,
        );
        continue;
      }
    }

    if (_looksLikeExpansion(item)) {
      final linkedBase = _baseBggId(item);
      if (linkedBase != null) {
        final base = byBggId[linkedBase];
        if (base != null && base.id != item.id && !_looksLikeExpansion(base)) {
          await linkToBase(
            expansionItem: item,
            baseItem: base,
            expansionBggId: expId,
          );
        }
      }
    }
  }

  for (final item in items) {
    if (linked.contains(item.id)) continue;
    if (item.parentGameId != null && item.parentGameId!.isNotEmpty) continue;
    if (bggLookups >= maxBggLookups) break;

    final expId = _itemBggId(item);
    if (expId == null) continue;
    if (item.metadata?['expansion_of_bgg_id'] != null) continue;
    if (_looksLikeExpansion(item)) continue;

    bggLookups++;
    final details = await BggService.getGameFullDetails(expId);
    final link = boardgameExpansionLinkFromDetails(details);
    if (!link.isExpansion || link.baseBggId == null) continue;

    final base = byBggId[link.baseBggId!];
    if (base == null || base.id == item.id || _looksLikeExpansion(base)) {
      continue;
    }

    await linkToBase(
      expansionItem: item,
      baseItem: base,
      expansionBggId: expId,
    );
  }

  if (merged > 0) {
    CollectionRefresh.instance.bump();
  }

  return BoardgameExpansionReconcileResult(
    mergedCount: merged,
    deletedCount: 0,
  );
}
