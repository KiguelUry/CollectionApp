import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bgg_catalog_game.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/profile_service.dart';
import '../services/collection_refresh.dart';
import '../widgets/add_item_options_dialog.dart';
import 'boardgame_cover.dart';
import 'boardgame_expansion_flow.dart';

/// Ajout depuis le catalogue BGG avec dialogue classique (comme les cartes).
Future<void> quickAddBoardgameFromCatalog(
  BuildContext context, {
  required BggCatalogGame game,
}) async {
  if (!context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Flexible(child: Text('Chargement des infos BGG…')),
          ],
        ),
      ),
    ),
  );

  Map<String, dynamic>? details;
  if (game.bggId.isNotEmpty) {
    details = await BggService.getGameFullDetails(game.bggId);
  }

  if (!context.mounted) return;
  Navigator.pop(context);

  final coverUrl = boardgameStorageImageUrl(
    details: details,
    catalogUrl: game.imageUrl,
  );

  await showDialog(
    context: context,
    builder: (dialogContext) => AddItemOptionsDialog(
      itemTitle: game.title,
      itemImageUrl: coverUrl,
      onConfirm: (options) async {
        final client = Supabase.instance.client;
        final userId = client.auth.currentUser!.id;

        try {
          await ProfileService().ensureCurrentUserProfile();
        } on PostgrestException catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  ProfileService.isMissingProfileFk(e)
                      ? ProfileService.missingProfileUserMessage()
                      : '$e',
                ),
              ),
            );
          }
          return;
        }

        int? playingTime;
        final pt = details?['playing_time'];
        if (pt is int && pt > 0) playingTime = pt;

        try {
          String message;
          if (!options.isWishlist &&
              game.bggId.isNotEmpty &&
              details != null) {
            if (!context.mounted) return;
            final expansionMsg = await insertBoardgameWithExpansionRules(
              context: context,
              title: game.title,
              bggId: game.bggId,
              bggDetails: details,
              imageUrl: coverUrl,
              isWishlist: false,
              quantity: options.quantity,
              locationId: options.locationId,
              groupId: options.groupId,
              locationUserId: options.locationUserId,
              minPlayers: details['min_players'] as int?,
              maxPlayers: details['max_players'] as int?,
              playingTime: playingTime,
            );
            if (expansionMsg != null) {
              message = expansionMsg;
            } else {
              final meta = <String, dynamic>{
                if (game.bggId.isNotEmpty) 'bgg_id': game.bggId,
              };
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
              final item = CollectionItem(
                id: '',
                title: game.title.trim(),
                category: CollectionCategory.boardgame,
                metadata: meta.isEmpty ? null : meta,
                imageUrl: coverUrl,
                isWishlist: options.isWishlist,
                quantity: options.quantity,
                locationId: options.locationId,
                groupId: options.groupId,
                minPlayers: details['min_players'] as int?,
                maxPlayers: details['max_players'] as int?,
                playingTime: playingTime,
              );
              await client.from('collection_items').insert(
                    item.toInsertJson(
                      isWishlist: options.isWishlist,
                      locationUserId: options.isWishlist
                          ? null
                          : (options.locationUserId ?? userId),
                      addedBy: userId,
                    ),
                  );
              message = options.isWishlist
                  ? '« ${game.title} » ajouté à la wishlist'
                  : '« ${game.title} » ajouté';
            }
          } else {
            final meta = <String, dynamic>{
              if (game.bggId.isNotEmpty) 'bgg_id': game.bggId,
            };
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
            final item = CollectionItem(
              id: '',
              title: game.title.trim(),
              category: CollectionCategory.boardgame,
              metadata: meta.isEmpty ? null : meta,
              imageUrl: coverUrl,
              isWishlist: options.isWishlist,
              quantity: options.quantity,
              locationId: options.locationId,
              groupId: options.groupId,
              minPlayers: details?['min_players'] as int?,
              maxPlayers: details?['max_players'] as int?,
              playingTime: playingTime,
            );
            await client.from('collection_items').insert(
                  item.toInsertJson(
                    isWishlist: options.isWishlist,
                    locationUserId: options.isWishlist
                        ? null
                        : (options.locationUserId ?? userId),
                    addedBy: userId,
                  ),
                );
            message = options.isWishlist
                ? '« ${game.title} » ajouté à la wishlist'
                : '« ${game.title} » ajouté';
          }
          CollectionRefresh.instance.bump();
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
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
        }
      },
    ),
  );
}
