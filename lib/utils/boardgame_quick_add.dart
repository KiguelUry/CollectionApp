import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bgg_catalog_game.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/profile_service.dart';
import '../widgets/add_item_options_dialog.dart';

/// Ajout depuis le catalogue BGG avec dialogue classique (comme les cartes).
Future<void> quickAddBoardgameFromCatalog(
  BuildContext context, {
  required BggCatalogGame game,
}) async {
  await showDialog(
    context: context,
    builder: (dialogContext) => AddItemOptionsDialog(
      itemTitle: game.title,
      itemImageUrl: game.imageUrl,
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

        Map<String, dynamic>? details;
        if (game.bggId.isNotEmpty) {
          details = await BggService.getGameFullDetails(game.bggId);
        }

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

        int? playingTime;
        final pt = details?['playing_time'];
        if (pt is int && pt > 0) playingTime = pt;

        final item = CollectionItem(
          id: '',
          title: game.title.trim(),
          category: CollectionCategory.boardgame,
          metadata: meta.isEmpty ? null : meta,
          imageUrl: game.imageUrl ?? details?['image_url'] as String?,
          isWishlist: options.isWishlist,
          quantity: options.quantity,
          locationId: options.locationId,
          groupId: options.groupId,
          minPlayers: details?['min_players'] as int?,
          maxPlayers: details?['max_players'] as int?,
          playingTime: playingTime,
        );

        try {
          await client.from('collection_items').insert(
                item.toInsertJson(
                  isWishlist: options.isWishlist,
                  locationUserId: options.isWishlist
                      ? null
                      : (options.locationUserId ?? userId),
                  addedBy: userId,
                ),
              );
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  options.isWishlist
                      ? '« ${game.title} » ajouté à la wishlist'
                      : '« ${game.title} » ajouté',
                ),
              ),
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
