import 'package:shared_preferences/shared_preferences.dart';

/// Préférences d'affichage communes aux grilles de collection.
class CollectionDisplayPreferences {
  CollectionDisplayPreferences._();
  static final CollectionDisplayPreferences instance =
      CollectionDisplayPreferences._();

  static const _keyGridColumns = 'collection_grid_mobile_columns_v1';

  int _gridMobileColumns = 3;
  bool _loaded = false;

  /// Colonnes sur mobile / web étroit (2 = grandes pochettes, 3 = densité).
  int get gridMobileColumns => _gridMobileColumns.clamp(2, 3);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_keyGridColumns);
    _gridMobileColumns = (raw == 2 || raw == 3) ? raw! : 3;
    _loaded = true;
  }

  Future<void> setGridMobileColumns(int columns) async {
    await load();
    final next = columns.clamp(2, 3);
    _gridMobileColumns = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyGridColumns, next);
  }

  Future<void> toggleGridMobileColumns() async {
    await setGridMobileColumns(gridMobileColumns == 3 ? 2 : 3);
  }
}
