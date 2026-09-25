import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../models/videogame_platform.dart';
import '../services/profile_service.dart';
import '../utils/catalog_hit_metadata.dart';
import '../utils/videogame_metadata.dart';
import '../widgets/add_item_options_dialog.dart';
import '../widgets/videogame_platform_picker.dart';

/// Ajout rapide d'un jeu vidéo depuis le catalogue / feed amis.
Future<bool> quickAddVideogameFromHit(
  BuildContext context,
  Map<String, String> hit,
) async {
  var meta = metadataFromCatalogHit(hit, CollectionCategory.videogame);
  final suggested = VideogamePlatform.inferFromText(hit['platform']);
  final platforms = await showVideogamePlatformPicker(
    context,
    suggested: suggested,
  );
  if (!context.mounted) return false;
  if (platforms != null && platforms.isNotEmpty) {
    meta = metadataWithPlatforms(meta, platforms);
  }

  var added = false;
  await showDialog(
    context: context,
    builder: (dialogContext) => AddItemOptionsDialog(
      itemTitle: hit['title'] ?? 'Jeu',
      itemImageUrl:
          hit['image_url']?.isNotEmpty == true ? hit['image_url'] : null,
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

        final item = CollectionItem(
          id: '',
          title: (hit['title'] ?? '').trim(),
          category: CollectionCategory.videogame,
          metadata: meta.isEmpty ? null : meta,
          imageUrl:
              hit['image_url']?.isNotEmpty == true ? hit['image_url'] : null,
          isWishlist: options.isWishlist,
          quantity: options.quantity,
          locationId: options.locationId,
          groupId: options.groupId,
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
          added = true;
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('« ${item.title} » ajouté')),
            );
          }
        } on PostgrestException catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$e')),
            );
          }
        }
      },
    ),
  );
  return added;
}
