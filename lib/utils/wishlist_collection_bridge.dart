import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../services/collection_refresh.dart';
import '../utils/whereabouts_persistence.dart';
import 'wishlist_promote.dart';

/// Ajoute 1 exemplaire en collection à partir d'une ligne wishlist (sans supprimer la wishlist).
Future<void> addOneToCollectionFromWishlist(CollectionItem wishItem) async {
  if (!wishItem.isWishlist) return;

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return;

  final existing = await findDuplicateRow(
    title: wishItem.title,
    categoryDb: wishItem.category.dbValue,
    isWishlist: false,
    subcategory: wishItem.subcategory,
    groupId: wishItem.groupId,
  );

  if (existing != null) {
    final id = existing['id'] as String;
    final qty = (existing['quantity'] as int?) ?? 0;
    await client
        .from('collection_items')
        .update({'quantity': qty + 1})
        .eq('id', id);
  } else {
    final meta = Map<String, dynamic>.from(wishItem.metadata ?? {});
    final draft = wishItem.copyWith(
      isWishlist: false,
      quantity: 1,
      metadata: meta,
      locationUserId: userId,
    );
    await client.from('collection_items').insert(
          buildCollectionItemInsertPayload(
            item: draft,
            addedBy: userId,
            isWishlist: false,
            defaultUserId: userId,
          ),
        );
  }

  CollectionRefresh.instance.bump();
}

/// Crée une ligne wishlist pour un jeu déjà en collection (ou incrémente si doublon wishlist).
Future<void> addToWishlistFromCollection(CollectionItem collectionItem) async {
  if (collectionItem.isWishlist) return;

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return;

  final existing = await findDuplicateRow(
    title: collectionItem.title,
    categoryDb: collectionItem.category.dbValue,
    isWishlist: true,
    subcategory: collectionItem.subcategory,
    groupId: collectionItem.groupId,
  );

  if (existing != null) return;

  final meta = Map<String, dynamic>.from(collectionItem.metadata ?? {});
  final draft = collectionItem.copyWith(
    isWishlist: true,
    quantity: 0,
    metadata: meta,
  );
  await client.from('collection_items').insert(
        buildCollectionItemInsertPayload(
          item: draft,
          addedBy: userId,
          isWishlist: true,
          defaultUserId: userId,
        ),
      );
  CollectionRefresh.instance.bump();
}

/// Retire la ligne wishlist (après confirmation utilisateur).
Future<void> removeWishlistRow(CollectionItem wishItem) async {
  if (!wishItem.isWishlist || wishItem.id.isEmpty) return;
  await Supabase.instance.client
      .from('collection_items')
      .delete()
      .eq('id', wishItem.id);
  CollectionRefresh.instance.bump();
}
