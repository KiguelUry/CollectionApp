import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/boardgame_expansion_service.dart';
import '../services/collection_refresh.dart';
import 'boardgame_expansion_flow.dart';
import 'boardgame_expansions.dart';

/// Résultat d'une passe de reconciliation extensions ↔ jeux de base.
class BoardgameExpansionReconcileResult {
  final int mergedCount;
  final int deletedCount;

  const BoardgameExpansionReconcileResult({
    this.mergedCount = 0,
    this.deletedCount = 0,
  });

  bool get changed => mergedCount > 0 || deletedCount > 0;
}

/// Rattache les extensions en double (legacy metadata ou orphelines).
Future<BoardgameExpansionReconcileResult> reconcileBoardgameExpansions({
  int maxBggLookups = 12,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return const BoardgameExpansionReconcileResult();

  final rows = await client
      .from('collection_items')
      .select()
      .eq('category', CollectionCategory.boardgame.dbValue)
      .eq('is_wishlist', false)
      .or('added_by.eq.$userId,location_user_id.eq.$userId');

  final items = (rows as List)
      .map((r) => CollectionItem.fromJson(r as Map<String, dynamic>))
      .toList();

  if (items.isEmpty) return const BoardgameExpansionReconcileResult();

  final service = BoardgameExpansionService();
  final byBggId = <String, CollectionItem>{};
  for (final item in items) {
    final id = item.metadata?['bgg_id']?.toString();
    if (id != null && id.isNotEmpty) byBggId[id] = item;
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
    if (expansionItem.parentGameId == baseItem.id) {
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

    final expId = item.metadata?['bgg_id']?.toString();
    if (expId == null || expId.isEmpty) continue;

    for (final other in items) {
      if (other.id == item.id || linked.contains(item.id)) continue;
      if (!ownedExpansionBggIds(other.metadata).contains(expId)) continue;
      if (other.isExpansion) continue;
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

    final expId = item.metadata?['bgg_id']?.toString();
    if (expId == null || expId.isEmpty) continue;

    final baseId = item.metadata?['expansion_of_bgg_id']?.toString() ??
        item.metadata?['base_game_bgg_id']?.toString();
    if (baseId != null && baseId.isNotEmpty) {
      final base = byBggId[baseId];
      if (base != null && base.id != item.id && !base.isExpansion) {
        await linkToBase(
          expansionItem: item,
          baseItem: base,
          expansionBggId: expId,
        );
        continue;
      }
    }

    if (item.metadata?['bgg_is_expansion'] == true || item.isExpansion) {
      final linkedBase = item.metadata?['base_game_bgg_id']?.toString();
      if (linkedBase != null && linkedBase.isNotEmpty) {
        final base = byBggId[linkedBase];
        if (base != null && base.id != item.id && !base.isExpansion) {
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

    final expId = item.metadata?['bgg_id']?.toString();
    if (expId == null || expId.isEmpty) continue;
    if (item.metadata?['expansion_of_bgg_id'] != null) continue;
    if (item.metadata?['bgg_is_expansion'] == true || item.isExpansion) {
      continue;
    }

    bggLookups++;
    final details = await BggService.getGameFullDetails(expId);
    final link = boardgameExpansionLinkFromDetails(details);
    if (!link.isExpansion || link.baseBggId == null) continue;

    final base = byBggId[link.baseBggId!];
    if (base == null || base.id == item.id || base.isExpansion) continue;

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
