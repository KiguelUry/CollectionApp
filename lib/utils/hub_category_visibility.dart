import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../models/user_collection_type.dart';
import '../services/category_hub_preferences.dart';
import '../services/user_collection_type_service.dart';
import '../utils/category_hub_order.dart';

/// Filtre tuiles hub selon préférences utilisateur.
Future<List<HubTileEntry>> loadVisibleHubTiles() async {
  await CategoryHubPreferences.instance.load();
  final customTypes = await UserCollectionTypeService().fetchMine();
  final all = await CategoryHubOrder.loadOrderedTiles(customTypes);
  return all.where((e) {
    if (e.category != null) {
      return CategoryHubPreferences.instance.isVisible(e.category!);
    }
    return true;
  }).toList();
}

List<CollectionCategory> visibleMenuCategories() {
  return CategoryHubPreferences.instance
      .filterVisible(CollectionCategory.menuValues);
}

Map<CollectionCategory, int> emptyCategoryCounts() {
  return {for (final c in visibleMenuCategories()) c: 0};
}
