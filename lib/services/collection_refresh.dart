import 'package:flutter/foundation.dart';

import 'book_series_service.dart';
import 'books_collection_cache.dart';
import 'inventory_service.dart';
import 'supabase_read_cache.dart';

/// Notifie les écrans collection qu'un ajout/suppression a eu lieu.
class CollectionRefresh extends ChangeNotifier {
  CollectionRefresh._();
  static final instance = CollectionRefresh._();

  void bump() {
    InventoryService.invalidateCache();
    BookSeriesService.invalidateSeriesCache();
    BookSeriesService.invalidateVolumeCache();
    BooksCollectionCache.instance.markStale();
    SupabaseReadCache.invalidate('collection_items_cat:');
    SupabaseReadCache.invalidate('my_groups:');
    SupabaseReadCache.invalidate('group_members:');
    SupabaseReadCache.invalidate('friendships:');
    SupabaseReadCache.invalidate('profile_privacy:');
    SupabaseReadCache.invalidate('card_meta:');
    notifyListeners();
  }
}
