import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
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

/// Rattache les extensions en double (ajoutées avant la nouvelle logique).
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

  final byBggId = <String, CollectionItem>{};
  for (final item in items) {
    final id = item.metadata?['bgg_id']?.toString();
    if (id != null && id.isNotEmpty) byBggId[id] = item;
  }

  final toDelete = <String>{};
  var merged = 0;
  var bggLookups = 0;

  Future<void> mergeIntoBase({
    required CollectionItem expansionItem,
    required CollectionItem baseItem,
    required String expansionBggId,
  }) async {
    if (toDelete.contains(expansionItem.id)) return;
    await attachExpansionToBaseItem(
      baseItem: baseItem,
      expansionBggId: expansionBggId,
    );
    toDelete.add(expansionItem.id);
    merged++;
  }

  for (final item in items) {
    final expId = item.metadata?['bgg_id']?.toString();
    if (expId == null || expId.isEmpty) continue;

    for (final other in items) {
      if (other.id == item.id || toDelete.contains(item.id)) continue;
      if (ownedExpansionBggIds(other.metadata).contains(expId)) {
        toDelete.add(item.id);
        merged++;
        break;
      }
    }
  }

  for (final item in items) {
    if (toDelete.contains(item.id)) continue;

    final expId = item.metadata?['bgg_id']?.toString();
    if (expId == null || expId.isEmpty) continue;

    final baseId = item.metadata?['expansion_of_bgg_id']?.toString();
    if (baseId != null && baseId.isNotEmpty) {
      final base = byBggId[baseId];
      if (base != null && base.id != item.id) {
        await mergeIntoBase(
          expansionItem: item,
          baseItem: base,
          expansionBggId: expId,
        );
        continue;
      }
    }

    if (item.metadata?['bgg_is_expansion'] == true) {
      final linkedBase = item.metadata?['base_game_bgg_id']?.toString();
      if (linkedBase != null && linkedBase.isNotEmpty) {
        final base = byBggId[linkedBase];
        if (base != null && base.id != item.id) {
          await mergeIntoBase(
            expansionItem: item,
            baseItem: base,
            expansionBggId: expId,
          );
        }
      }
    }
  }

  for (final item in items) {
    if (toDelete.contains(item.id)) continue;
    if (bggLookups >= maxBggLookups) break;

    final expId = item.metadata?['bgg_id']?.toString();
    if (expId == null || expId.isEmpty) continue;
    if (item.metadata?['expansion_of_bgg_id'] != null) continue;
    if (item.metadata?['bgg_is_expansion'] == true) continue;

    bggLookups++;
    final details = await BggService.getGameFullDetails(expId);
    final link = boardgameExpansionLinkFromDetails(details);
    if (!link.isExpansion || link.baseBggId == null) continue;

    final base = byBggId[link.baseBggId!];
    if (base == null || base.id == item.id) continue;

    await mergeIntoBase(
      expansionItem: item,
      baseItem: base,
      expansionBggId: expId,
    );
  }

  for (final id in toDelete) {
    await client.from('collection_items').delete().eq('id', id);
  }

  if (toDelete.isNotEmpty) {
    CollectionRefresh.instance.bump();
  }

  return BoardgameExpansionReconcileResult(
    mergedCount: merged,
    deletedCount: toDelete.length,
  );
}
