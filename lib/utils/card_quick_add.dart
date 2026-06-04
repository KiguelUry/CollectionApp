import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/card_subcategory.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/card_catalog_service.dart';
import '../services/profile_service.dart';
import '../models/tcg_set_info.dart';
import '../widgets/add_item_options_dialog.dart';

/// Ajout rapide d'une carte depuis le navigateur de sets.
Future<void> quickAddCardFromCatalog(
  BuildContext context, {
  required CardSubcategory subcategory,
  required String title,
  String? imageUrl,
  Map<String, dynamic>? metadata,
}) async {
  final meta = metadata ?? {};
  await showDialog(
    context: context,
    builder: (dialogContext) => AddItemOptionsDialog(
      itemTitle: title,
      itemImageUrl: imageUrl,
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
          title: title.trim(),
          category: CollectionCategory.card,
          subcategory: subcategory.dbValue,
          metadata: meta,
          imageUrl: imageUrl,
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
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('« $title » ajouté')),
            );
          }
        } on PostgrestException catch (e) {
          if (context.mounted) {
            final msg = _insertErrorMessage(e);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        }
      },
    ),
  );
}

Future<void> quickAddTcgCatalogCard(
  BuildContext context, {
  required CardSubcategory subcategory,
  required TcgCatalogCard card,
}) {
  return quickAddCardFromCatalog(
    context,
    subcategory: subcategory,
    title: card.name,
    imageUrl: card.imageUrl,
    metadata: CardCatalogService.metadataFromTcgCard(card, subcategory),
  );
}

String _insertErrorMessage(PostgrestException e) {
  if (ProfileService.isMissingProfileFk(e)) {
    return ProfileService.missingProfileUserMessage();
  }
  final m = e.message.toLowerCase();
  if (m.contains('subcategory_check')) {
    return 'Univers carte non reconnu en base. '
        'Exécute supabase/schema_collection_item_subcategory.sql '
        'dans Supabase (SQL Editor).';
  }
  return e.message;
}
