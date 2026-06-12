import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../services/profile_service.dart';
import '../utils/wishlist_promote.dart';
import '../widgets/add_item_options_dialog.dart';

/// Ajoute un objet vu chez un ami dans ta collection ou ta wishlist.
Future<void> showCopyFriendItemSheet(
  BuildContext context, {
  required CollectionItem source,
  required String friendUsername,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '« ${source.title} »',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Text(
            'Vu dans la collection de $friendUsername',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.inventory_2_outlined, color: source.category.color),
            title: const Text('Ajouter à ma collection'),
            subtitle: const Text('Possédé — avec emplacement si besoin'),
            onTap: () => Navigator.pop(ctx, 'collection'),
          ),
          ListTile(
            leading: Icon(Icons.favorite_border, color: Colors.amber.shade800),
            title: const Text('Ajouter à ma wishlist'),
            subtitle: const Text('Objet que tu veux acquérir'),
            onTap: () => Navigator.pop(ctx, 'wishlist'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (!context.mounted || choice == null) return;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => AddItemOptionsDialog(
      itemTitle: source.title,
      itemImageUrl: source.imageUrl,
      defaultWishlist: choice == 'wishlist',
      onConfirm: (options) => _insertCopy(
        dialogCtx,
        source: source,
        options: options,
      ),
    ),
  );
}

Future<void> _insertCopy(
  BuildContext dialogContext, {
  required CollectionItem source,
  required AddItemOptions options,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser!.id;

  try {
    await ProfileService().ensureCurrentUserProfile();

    final existing = await findDuplicateRow(
      title: source.title,
      categoryDb: source.category.dbValue,
      isWishlist: options.isWishlist,
      subcategory: source.subcategory,
      groupId: options.groupId,
    );
    var message = '« ${source.title} » ajouté';

    if (existing != null) {
      if (options.isWishlist) {
        message = 'Déjà dans ta wishlist';
      } else {
        final newQty =
            ((existing['quantity'] as int?) ?? 1) + options.quantity;
        await client
            .from('collection_items')
            .update({'quantity': newQty})
            .eq('id', existing['id']);
        message = 'Quantité mise à jour ($newQty)';
      }
    } else {
      final meta = Map<String, dynamic>.from(source.metadata ?? {});
      meta['copied_from_friend'] = true;

      final item = CollectionItem(
        id: '',
        title: source.title.trim(),
        category: source.category,
        subcategory: source.subcategory,
        metadata: meta.isEmpty ? null : meta,
        imageUrl: source.imageUrl,
        isWishlist: options.isWishlist,
        quantity: options.quantity,
        locationId: options.locationId,
        groupId: options.groupId,
        minPlayers: source.minPlayers,
        maxPlayers: source.maxPlayers,
        playingTime: source.playingTime,
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
      if (options.isWishlist) {
        message = '« ${source.title} » ajouté à la wishlist';
      }
    }

    if (dialogContext.mounted) {
      Navigator.pop(dialogContext);
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  } on PostgrestException catch (e) {
    if (dialogContext.mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text(
            ProfileService.isMissingProfileFk(e)
                ? ProfileService.missingProfileUserMessage()
                : 'Impossible d\'ajouter : ${e.message}',
          ),
        ),
      );
    }
  }
}
