import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection_category.dart';

/// Visibilité des catégories sur le hub (masquage local).
///
/// Les catégories [CollectionCategory.labCategories] sont masquées une fois
/// par défaut (focus produit) ; l’utilisateur peut les réactiver dans
/// « Gestion des collections ».
class CategoryHubPreferences {
  CategoryHubPreferences._();
  static final CategoryHubPreferences instance = CategoryHubPreferences._();

  static const _keyHidden = 'hub_hidden_categories_v1';
  /// Seed focus : masquer lab (montres, tech, nature, restos) sans supprimer le code.
  static const _keyFocusLabSeed = 'hub_focus_lab_default_v2';
  Set<String> _hiddenDb = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _hiddenDb = (prefs.getStringList(_keyHidden) ?? []).toSet();

    if (!(prefs.getBool(_keyFocusLabSeed) ?? false)) {
      for (final c in CollectionCategory.labCategories) {
        _hiddenDb.add(c.dbValue);
      }
      await prefs.setStringList(_keyHidden, _hiddenDb.toList());
      await prefs.setBool(_keyFocusLabSeed, true);
    }

    _loaded = true;
  }

  bool isVisible(CollectionCategory cat) => !_hiddenDb.contains(cat.dbValue);

  bool isLab(CollectionCategory cat) =>
      CollectionCategory.labCategories.contains(cat);

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
