import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../services/collection_refresh.dart';

/// Bascule le favori / priorité wishlist (`metadata.is_favorite`) et notifie la grille.
Future<CollectionItem> toggleItemFavorite(CollectionItem item) async {
  final next = !item.isFavorite;
  final updated = item.withFavorite(next);
  await Supabase.instance.client
      .from('collection_items')
      .update({'metadata': updated.metadata})
      .eq('id', item.id);
  CollectionRefresh.instance.bump();
  return updated;
}
