import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection_category.dart';

/// Visibilité des catégories sur le hub (masquage local).
class CategoryHubPreferences {
  CategoryHubPreferences._();
  static final CategoryHubPreferences instance = CategoryHubPreferences._();

  static const _keyHidden = 'hub_hidden_categories_v1';
  Set<String> _hiddenDb = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _hiddenDb = (prefs.getStringList(_keyHidden) ?? []).toSet();
    _loaded = true;
  }

  bool isVisible(CollectionCategory cat) => !_hiddenDb.contains(cat.dbValue);

  Future<void> setVisible(CollectionCategory cat, bool visible) async {
    await load();
    if (visible) {
      _hiddenDb.remove(cat.dbValue);
    } else {
      _hiddenDb.add(cat.dbValue);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyHidden, _hiddenDb.toList());
  }

  List<CollectionCategory> filterVisible(Iterable<CollectionCategory> cats) {
    return cats.where(isVisible).toList();
  }
}
