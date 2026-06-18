import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bgg_catalog_game.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/profile_service.dart';
import '../services/user_boardgame_collection_service.dart';

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
    imageUrl: game.imageUrl ?? details?['image_url'] as String?,
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
    final item = _itemFromGame(game, details, isWishlist: false, userId: userId);
    await client.from('collection_items').insert(
          item.toInsertJson(
            isWishlist: false,
            locationUserId: userId,
            addedBy: userId,
          ),
        );
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
