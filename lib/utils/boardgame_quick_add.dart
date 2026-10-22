import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bgg_catalog_game.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/collection_change_history_service.dart';
import '../services/item_group_service.dart';
import '../services/profile_service.dart';
import '../services/collection_refresh.dart';
import '../widgets/add_item_options_dialog.dart';
import '../utils/whereabouts_persistence.dart';
import '../utils/wishlist_promote.dart';
import 'boardgame_cover.dart';
import 'boardgame_display.dart';
import 'boardgame_expansion_flow.dart';

/// Ajout depuis le catalogue BGG avec dialogue classique (comme les cartes).
Future<void> quickAddBoardgameFromCatalog(
  BuildContext context, {
  required BggCatalogGame game,
  bool defaultWishlist = false,
  bool showCrowdfundingSearch = false,
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
  final bggAvg = details != null
      ? parseBggAvgRating(details['bgg_avg_rating'])
      : null;

  final detailTitle = details?['title']?.toString().trim();
  final title = (detailTitle != null && detailTitle.isNotEmpty)
      ? detailTitle
      : game.title;
  final year = details?['year_published'] is int
      ? details!['year_published'] as int
      : int.tryParse('${details?['year_published'] ?? ''}');
  final minP = details?['min_players'] is int
      ? details!['min_players'] as int
      : int.tryParse('${details?['min_players'] ?? ''}');
  final maxP = details?['max_players'] is int
      ? details!['max_players'] as int
      : int.tryParse('${details?['max_players'] ?? ''}');
  final desc = details?['bgg_description']?.toString() ??
      details?['bgg_short_description']?.toString();
  int? playingTime;
  final pt = details?['playing_time'];
  if (pt is int && pt > 0) {
    playingTime = pt;
  } else {
    playingTime = int.tryParse('$pt');
    if (playingTime != null && playingTime <= 0) playingTime = null;
  }

  await showDialog(
    context: context,
    builder: (dialogContext) => AddItemOptionsDialog(
      itemTitle: title,
      itemImageUrl: coverUrl,
      bggAvgRating: bggAvg,
      defaultWishlist: defaultWishlist,
      yearPublished: year,
      minPlayers: minP,
      maxPlayers: maxP,
      playingTime: playingTime,
      description: desc,
      bggId: game.bggId,
      showCrowdfundingSearch: showCrowdfundingSearch ||
          (year != null && year > DateTime.now().year),
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

        if (options.isWishlist) {
          final dup = await findWishlistDuplicate(
            title: title,
            categoryDb: CollectionCategory.boardgame.dbValue,
            bggId: game.bggId.isNotEmpty ? game.bggId : null,
            groupId: options.groupId,
          );
          if (dup != null) {
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Déjà dans ta wishlist')),
              );
            }
            return;
          }
        }

        final detailsMap = details;

        try {
          String message;
          if (!options.isWishlist &&
              game.bggId.isNotEmpty &&
              detailsMap != null) {
            if (!context.mounted) return;
            final expansionMsg = await insertBoardgameWithExpansionRules(
              context: context,
              title: title,
              bggId: game.bggId,
              bggDetails: detailsMap,
              imageUrl: coverUrl,
              isWishlist: false,
              quantity: options.quantity,
              locationId: options.locationId,
              groupId: options.groupId,
              locationUserId: options.locationUserId,
              minPlayers: detailsMap['min_players'] as int?,
              maxPlayers: detailsMap['max_players'] as int?,
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
                'bgg_short_description',
                'bgg_avg_rating',
                'bgg_best_players',
                'bgg_gallery_urls',
              ]) {
                final v = detailsMap[key];
                if (v != null) meta[key] = v;
              }
              if (options.isWishlist) {}
              final item = CollectionItem(
                id: '',
                title: title.trim(),
                category: CollectionCategory.boardgame,
                metadata: meta.isEmpty ? null : meta,
                imageUrl: coverUrl,
                isWishlist: options.isWishlist,
                quantity: options.quantity,
                locationId: options.locationId,
                groupId: options.groupId,
                minPlayers: detailsMap['min_players'] as int?,
                maxPlayers: detailsMap['max_players'] as int?,
                playingTime: playingTime,
              );
              final payload = buildCollectionItemInsertPayload(
                item: item,
                addedBy: userId,
                isWishlist: options.isWishlist,
                holderLabel: options.holderLabel,
                defaultUserId: userId,
              );
              final inserted = await client
                  .from('collection_items')
                  .insert(payload)
                  .select()
                  .single();
              final created = CollectionItem.fromJson(
                Map<String, dynamic>.from(inserted as Map),
              );
              await CollectionChangeHistoryService.instance.recordAdded(created);
              if (options.groupId != null &&
                  options.groupId!.isNotEmpty &&
                  !options.isWishlist) {
                final saved = created.copyWith(
                  metadata: Map<String, dynamic>.from(
                    payload['metadata'] as Map? ?? {},
                  ),
                  locationUserId: payload['location_user_id'] as String?,
                  groupId: options.groupId,
                );
                await ItemGroupService().syncItemGroupsWithItem(saved, [
                  options.groupId!,
                ]);
              }
              message = options.isWishlist
                  ? '« $title » ajouté à la wishlist'
                  : '« $title » ajouté';
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
                'bgg_short_description',
                'bgg_avg_rating',
                'bgg_best_players',
                'bgg_gallery_urls',
              ]) {
                final v = details[key];
                if (v != null) meta[key] = v;
              }
            }
            final item = CollectionItem(
              id: '',
              title: title.trim(),
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
            final payload = buildCollectionItemInsertPayload(
              item: item,
              addedBy: userId,
              isWishlist: options.isWishlist,
              holderLabel: options.holderLabel,
              defaultUserId: userId,
            );
            final inserted = await client
                .from('collection_items')
                .insert(payload)
                .select()
                .single();
            final created = CollectionItem.fromJson(
              Map<String, dynamic>.from(inserted as Map),
            );
            await CollectionChangeHistoryService.instance.recordAdded(created);
            if (options.groupId != null &&
                options.groupId!.isNotEmpty &&
                !options.isWishlist) {
              final saved = created.copyWith(
                metadata: Map<String, dynamic>.from(
                  payload['metadata'] as Map? ?? {},
                ),
                locationUserId: payload['location_user_id'] as String?,
                groupId: options.groupId,
              );
              await ItemGroupService().syncItemGroupsWithItem(saved, [
                options.groupId!,
              ]);
            }
            message = options.isWishlist
                ? '« $title » ajouté à la wishlist'
                : '« $title » ajouté';
          }
          CollectionRefresh.instance.bump();
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
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
