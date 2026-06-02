import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/card_subcategory.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../models/tcg_set_info.dart';
import '../services/card_catalog_service.dart';
import '../services/profile_service.dart';

/// Ajout immédiat (×1, chez moi) sans ouvrir le dialogue.
Future<bool> silentAddTcgCard(
  BuildContext context, {
  required CardSubcategory subcategory,
  required TcgCatalogCard card,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser!.id;

  try {
    await ProfileService().ensureCurrentUserProfile();
    final item = CollectionItem(
      id: '',
      title: card.name.trim(),
      category: CollectionCategory.card,
      subcategory: subcategory.dbValue,
      metadata: CardCatalogService.metadataFromTcgCard(card, subcategory),
      imageUrl: card.imageUrl,
      isWishlist: false,
      quantity: 1,
      addedBy: userId,
    );
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

/// Dialogue léger pour ajouter plusieurs cartes d'un coup.
Future<void> showBulkAddCardsDialog(
  BuildContext context, {
  required CardSubcategory subcategory,
  required List<TcgCatalogCard> cards,
  VoidCallback? onDone,
}) async {
  if (cards.isEmpty) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Ajouter ${cards.length} carte${cards.length > 1 ? 's' : ''} ?'),
      content: Text(
        cards.length <= 8
            ? cards.map((c) => '· ${c.name}').join('\n')
            : '${cards.take(6).map((c) => '· ${c.name}').join('\n')}\n… et ${cards.length - 6} autres',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Ajouter ${cards.length}'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  var ok = 0;
  for (final card in cards) {
    final added = await silentAddTcgCard(context, subcategory: subcategory, card: card);
    if (added) ok++;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$ok / ${cards.length} carte(s) ajoutée(s)')),
    );
    onDone?.call();
  }
}
