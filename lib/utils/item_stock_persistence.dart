import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../services/collection_refresh.dart';
import 'transaction_history.dart';

/// Met à jour la quantité possédée (0 autorisé).
Future<void> persistOwnedQuantity({
  required String itemId,
  required int quantity,
}) async {
  await Supabase.instance.client
      .from('collection_items')
      .update({'quantity': quantity.clamp(0, 9999)})
      .eq('id', itemId);
  CollectionRefresh.instance.bump();
}

/// Enregistre une vente : historique + quantité -1.
Future<int> recordSale({
  required CollectionItem item,
  required double? salePrice,
}) async {
  if (item.id.isEmpty || item.isWishlist) return item.quantity;
  final nextQty = (item.quantity - 1).clamp(0, 9999);
  final meta = metadataWithTransaction(
    item.metadata,
    TransactionRecord(
      kind: 'sold',
      date: DateTime.now(),
      salePrice: salePrice,
    ),
  );
  await Supabase.instance.client.from('collection_items').update({
    'quantity': nextQty,
    'metadata': meta,
    if (nextQty == 0) 'is_for_sale': false,
    if (nextQty == 0) 'is_sold': false,
  }).eq('id', item.id);
  CollectionRefresh.instance.bump();
  return nextQty;
}

/// Enregistre un échange : historique + quantité -1.
Future<int> recordTrade({
  required CollectionItem item,
  required String tradedFor,
}) async {
  if (item.id.isEmpty || item.isWishlist) return item.quantity;
  final nextQty = (item.quantity - 1).clamp(0, 9999);
  final meta = metadataWithTransaction(
    item.metadata,
    TransactionRecord(
      kind: 'traded',
      date: DateTime.now(),
      tradedFor: tradedFor,
    ),
  );
  await Supabase.instance.client.from('collection_items').update({
    'quantity': nextQty,
    'metadata': meta,
    if (nextQty == 0) 'is_for_sale': false,
  }).eq('id', item.id);
  CollectionRefresh.instance.bump();
  return nextQty;
}
