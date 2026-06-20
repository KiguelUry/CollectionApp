import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bgg_catalog_game.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/profile_service.dart';
import '../services/user_boardgame_collection_service.dart';
import '../services/boardgame_expansion_service.dart';
import '../services/collection_refresh.dart';
import 'boardgame_cover.dart';
import 'boardgame_expansion_flow.dart';
import 'boardgame_expansions.dart';

Future<Map<String, dynamic>?> _resolveBggDetails(BggCatalogGame game) async {
  if (game.bggId.isEmpty) return null;
  return BggService.getGameFullDetails(game.bggId);
}

CollectionItem _itemFromGame(
  BggCatalogGame game,
  Map<String, dynamic>? details, {
  required bool isWishlist,
  required String userId,
}) {
  final meta = <String, dynamic>{};
  if (game.bggId.isNotEmpty) meta['bgg_id'] = game.bggId;
  if (details != null) {
    for (final key in [
      'year_published',
      'min_age',
      'bgg_categories',
      'bgg_is_expansion',
      'base_game_bgg_id',
      'base_game_title',
    ]) {
      final v = details[key];
      if (v != null) meta[key] = v;
    }
  }

  int? minPlayers;
  int? maxPlayers;
  int? playingTime;
  if (details != null) {
    minPlayers = details['min_players'] as int?;
    maxPlayers = details['max_players'] as int?;
    final pt = details['playing_time'];
    if (pt is int && pt > 0) playingTime = pt;
  }

  return CollectionItem(
    id: '',
    title: game.title.trim(),
    category: CollectionCategory.boardgame,
    metadata: meta.isEmpty ? null : meta,
    imageUrl: boardgameStorageImageUrl(
      details: details,
      catalogUrl: game.imageUrl,
    ),
    isWishlist: isWishlist,
    quantity: 1,
    addedBy: userId,
    minPlayers: minPlayers,
    maxPlayers: maxPlayers,
    playingTime: playingTime,
  );
}

Future<bool> silentAddBoardgame(
  BuildContext context, {
  required BggCatalogGame game,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return false;

  try {
    await ProfileService().ensureCurrentUserProfile();
    final details = await _resolveBggDetails(game);
    if (game.bggId.isNotEmpty && details != null) {
      final link = boardgameExpansionLinkFromDetails(details);
      if (link.isExpansion && link.baseBggId != null) {
        final service = BoardgameExpansionService();
        final base = await service.findBaseByBggId(link.baseBggId!);
        if (base != null) {
          await service.linkExpansionToBase(
            base: base,
            expansionBggId: game.bggId,
            title: game.title,
            bggDetails: details,
            imageUrl: game.imageUrl,
            minPlayers: details['min_players'] as int?,
            maxPlayers: details['max_players'] as int?,
            playingTime: details['playing_time'] is int
                ? details['playing_time'] as int
                : null,
          );
          return true;
        }
        await service.insertOrphanExpansion(
          title: game.title.trim(),
          expansionBggId: game.bggId,
          baseBggId: link.baseBggId!,
          baseTitle: link.baseTitle,
          bggDetails: details,
          imageUrl: game.imageUrl,
          minPlayers: details['min_players'] as int?,
          maxPlayers: details['max_players'] as int?,
          playingTime: details['playing_time'] is int
              ? details['playing_time'] as int
              : null,
        );
        CollectionRefresh.instance.bump();
        return true;
      }
    }
    final item = _itemFromGame(game, details, isWishlist: false, userId: userId);
    await client.from('collection_items').insert(
          item.toInsertJson(
            isWishlist: false,
            locationUserId: userId,
            addedBy: userId,
          ),
        );
    CollectionRefresh.instance.bump();
    return true;
  } on PostgrestException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ProfileService.isMissingProfileFk(e)
                ? ProfileService.missingProfileUserMessage()
                : e.message,
          ),
        ),
      );
    }
    return false;
  } catch (_) {
    return false;
  }
}

Future<bool> silentAddBoardgameToWishlist(
  BuildContext context, {
  required BggCatalogGame game,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return false;

  try {
    await ProfileService().ensureCurrentUserProfile();
    final details = await _resolveBggDetails(game);
    final item = _itemFromGame(game, details, isWishlist: true, userId: userId);
    await client.from('collection_items').insert(
          item.toInsertJson(
            isWishlist: true,
            locationUserId: null,
            addedBy: userId,
          ),
        );
    CollectionRefresh.instance.bump();
    return true;
  } on PostgrestException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ProfileService.isMissingProfileFk(e)
                ? ProfileService.missingProfileUserMessage()
                : e.message,
          ),
        ),
      );
    }
    return false;
  } catch (_) {
    return false;
  }
}

Future<bool> silentRemoveBoardgame({
  required BggCatalogGame game,
}) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return false;

  if (game.bggId.isNotEmpty) {
    final service = BoardgameExpansionService();
    final rows = await Supabase.instance.client
        .from('collection_items')
        .select('id, title, metadata, parent_game_id')
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$userId,location_user_id.eq.$userId');

    for (final row in rows as List) {
      final meta = row['metadata'] as Map<String, dynamic>?;
      if (meta?['bgg_id']?.toString() == game.bggId &&
          row['parent_game_id'] != null) {
        final parentId = row['parent_game_id'] as String;
        final parentRows = await Supabase.instance.client
            .from('collection_items')
            .select('id, metadata')
            .eq('id', parentId)
            .maybeSingle();
        if (parentRows != null) {
          final parent = CollectionItem.fromJson(
            Map<String, dynamic>.from(parentRows),
          );
          await service.unlinkExpansionFromBase(
            base: parent,
            expansionBggId: game.bggId,
          );
          CollectionRefresh.instance.bump();
          return true;
        }
      }

      final owned = ownedExpansionBggIds(meta).toSet();
      if (!owned.contains(game.bggId)) continue;
      owned.remove(game.bggId);
      final updated = metadataWithOwnedExpansions(meta, owned.toList());
      await Supabase.instance.client
          .from('collection_items')
          .update({'metadata': updated})
          .eq('id', row['id']);
      CollectionRefresh.instance.bump();
      return true;
    }
  }

  final ok = await UserBoardgameCollectionService().removeOwnedByCatalogKey(
    game.catalogKey,
  );
  if (ok) CollectionRefresh.instance.bump();
  return ok;
}

Future<bool> toggleBoardgameWishlist(
  BuildContext context, {
  required BggCatalogGame game,
  required bool currentlyInWishlist,
}) async {
  if (currentlyInWishlist) {
    return UserBoardgameCollectionService().removeWishlistByCatalogKey(
      game.catalogKey,
    );
  }
  return silentAddBoardgameToWishlist(context, game: game);
}
