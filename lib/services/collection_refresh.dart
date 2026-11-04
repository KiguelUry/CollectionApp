import 'package:flutter/foundation.dart';

import 'book_series_service.dart';
import 'inventory_service.dart';

/// Notifie les écrans collection qu'un ajout/suppression a eu lieu.
class CollectionRefresh extends ChangeNotifier {
  CollectionRefresh._();
  static final instance = CollectionRefresh._();

  void bump() {
    InventoryService.invalidateCache();
    BookSeriesService.invalidateSeriesCache();
    notifyListeners();
  }
}
