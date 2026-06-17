import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection_category.dart';

const _prefsKey = 'category_hub_order_v1';

/// Ordre personnalisé des tuiles sur l'écran « Collections ».
class CategoryHubOrder {
  static Future<List<CollectionCategory>> loadOrderedMenuCategories() async {
    final defaults = CollectionCategory.menuValues;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey);
    if (saved == null || saved.isEmpty) return List.from(defaults);

    final byValue = {for (final c in defaults) c.dbValue: c};
    final ordered = <CollectionCategory>[];
    for (final id in saved) {
      final cat = byValue.remove(id);
      if (cat != null) ordered.add(cat);
    }
    ordered.addAll(byValue.values);
    return ordered;
  }

  static Future<void> saveOrder(List<CollectionCategory> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      categories.map((c) => c.dbValue).toList(),
    );
  }
}
