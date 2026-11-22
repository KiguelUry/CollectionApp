import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/collection_item.dart';
import '../services/collection_refresh.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../utils/wishlist_promote.dart';
import '../widgets/add_item_options_dialog.dart';

/// Objets en cours d'ajout (clé catalogue) : bloque les double / triple taps.
final Set<String> _inFlight = {};

String _catalogKey(CollectionItem item) {
  final bgg = item.metadata?['bgg_id']?.toString().trim();
  if (bgg != null && bgg.isNotEmpty) return 'bgg:$bgg';
  return '${item.category.dbValue}|${item.title.trim().toLowerCase()}';
}

String? _bggIdOf(CollectionItem item) {
  final raw = item.metadata?['bgg_id']?.toString().trim();
  return raw == null || raw.isEmpty ? null : raw;
}

/// Métadonnées copiées depuis l'objet d'un ami : on garde le catalogue
/// (bgg_id, année, notes BGG…) mais pas l'historique perso de l'ami.
Map<String, dynamic>? copiedFriendMetadata(CollectionItem source) {
  final meta = Map<String, dynamic>.from(source.metadata ?? {});
  for (final key in const [
    'boardgame_plays',
    'games_played',
    'score_template',
    'score_presets',
    'holder_label',
    'group_ids',
    'is_favorite',
    'disposition',
    'copy_label',
    'personal_rating',
    'merchant',
    'warranty_end',
  ]) {
    meta.remove(key);
  }
  meta['copied_from_friend'] = true;
  return meta;
}

/// Doublon chez moi (wishlist puis collection), par `bgg_id` puis titre.
Future<({bool owned, bool wishlist})> findMyCopyOf(CollectionItem source) async {
  final bgg = _bggIdOf(source);
  final wish = await findWishlistDuplicate(
    title: source.title,
    categoryDb: source.category.dbValue,
    bggId: bgg,
  );
  final owned = await findOwnedDuplicate(
    title: source.title,
    categoryDb: source.category.dbValue,
    bggId: bgg,
  );
  return (owned: owned != null, wishlist: wish != null);
}

/// Ajoute directement l'objet d'un ami à ma wishlist (sans modale).
/// Retourne le message à afficher.
Future<String> addFriendItemToWishlist(CollectionItem source) async {
  final key = _catalogKey(source);
  if (!_inFlight.add(key)) return 'Ajout déjà en cours…';
  try {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return 'Connecte-toi pour ajouter à ta wishlist';
    await ProfileService().ensureCurrentUserProfile();

    final mine = await findMyCopyOf(source);
    if (mine.owned) return 'Tu possèdes déjà « ${source.title} »';
    if (mine.wishlist) return '« ${source.title} » est déjà dans ta wishlist';

    final item = CollectionItem(
      id: '',
      title: source.title.trim(),
      category: source.category,
      subcategory: source.subcategory,
      metadata: copiedFriendMetadata(source),
      imageUrl: source.imageUrl,
      isWishlist: true,
      quantity: 0,
      minPlayers: source.minPlayers,
      maxPlayers: source.maxPlayers,
      playingTime: source.playingTime,
    );
    await client
        .from('collection_items')
        .insert(item.toInsertJson(isWishlist: true, addedBy: userId));
    CollectionRefresh.instance.bump();
    return '« ${source.title} » ajouté à ta wishlist';
  } finally {
    _inFlight.remove(key);
  }
}

/// Envoie une demande d'emprunt au propriétaire (notification in-app).
Future<String> requestBorrowFriendItem(
  CollectionItem source, {
  String? message,
}) async {
  final ownerId = source.addedBy;
  final me = Supabase.instance.client.auth.currentUser?.id;
  if (ownerId == null || ownerId.isEmpty) {
    return 'Propriétaire introuvable';
  }
  if (ownerId == me) return 'C\'est ton propre jeu';
  final payload = <String, dynamic>{
    'kind': 'borrow_request',
    'item_id': source.id,
    'item_title': source.title,
    'item_category': source.category.dbValue,
    if (source.imageUrl != null) 'image_url': source.imageUrl,
    if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
  };
  final dedupe = 'borrow:${source.id}:$me';
  try {
    await NotificationService.instance.send(
      recipientId: ownerId,
      type: AppNotificationType.borrowRequest,
      payload: payload,
      dedupeKey: dedupe,
      replaceExisting: true,
    );
  } on PostgrestException {
    // Migration `schema_social_v2.sql` pas encore jouée : type inconnu côté
    // serveur → on passe par une recommandation typée « borrow_request ».
    await NotificationService.instance.send(
      recipientId: ownerId,
      type: AppNotificationType.itemRecommendation,
      payload: payload,
      dedupeKey: dedupe,
      replaceExisting: true,
    );
  }
  return 'Demande d\'emprunt envoyée 🤝';
}

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

  if (choice == 'wishlist') {
    final messenger = ScaffoldMessenger.of(context);
    final msg = await addFriendItemToWishlist(source);
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => AddItemOptionsDialog(
      itemTitle: source.title,
      itemImageUrl: source.imageUrl,
      defaultWishlist: false,
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
  final key = _catalogKey(source);
  if (!_inFlight.add(key)) return;

  try {
    await ProfileService().ensureCurrentUserProfile();

    final existing = await findDuplicateRow(
      title: source.title,
      categoryDb: source.category.dbValue,
      isWishlist: options.isWishlist,
      subcategory: source.subcategory,
      groupId: options.groupId,
      bggId: _bggIdOf(source),
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
      final item = CollectionItem(
        id: '',
        title: source.title.trim(),
        category: source.category,
        subcategory: source.subcategory,
        metadata: copiedFriendMetadata(source),
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
    CollectionRefresh.instance.bump();

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
  } finally {
    _inFlight.remove(key);
  }
}
