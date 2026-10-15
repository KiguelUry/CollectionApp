import '../models/collection_category.dart';
import '../services/category_hub_preferences.dart';

/// Source de vérité unique des catégories actives (affichées sur le hub).
///
/// Stats, graphiques et tirages aléatoires ne comptent que ces catégories :
/// les catégories masquées (lab, retirées) gardent leurs données en base
/// mais n'apparaissent nulle part dans les totaux.
class ActiveCategories {
  ActiveCategories._();

  /// Catégories du menu non masquées par l'utilisateur.
  static Set<CollectionCategory> resolve({
    required Set<String> hiddenDbValues,
  }) {
    return CollectionCategory.menuValues
        .where((c) => !hiddenDbValues.contains(c.dbValue))
        .toSet();
  }

  /// Charge les préférences hub puis retourne les catégories actives.
  static Future<Set<CollectionCategory>> load() async {
    final prefs = CategoryHubPreferences.instance;
    await prefs.load();
    return prefs.filterVisible(CollectionCategory.menuValues).toSet();
  }

  static bool containsDbValue(
    Set<CollectionCategory> active,
    String? dbValue,
  ) {
    if (dbValue == null || dbValue.isEmpty) return false;
    // fromDbValue retombe sur boardgame pour les valeurs inconnues.
    const aliases = {'manga', 'wildlife'};
    final known = aliases.contains(dbValue) ||
        CollectionCategory.values.any((c) => c.dbValue == dbValue);
    if (!known) return false;
    return active.contains(CollectionCategory.fromDbValue(dbValue));
  }

  /// Filtre des lignes Supabase brutes (`category` en dbValue).
  static List<Map<String, dynamic>> filterRows(
    Iterable<Map<String, dynamic>> rows,
    Set<CollectionCategory> active,
  ) {
    return rows
        .where((r) => containsDbValue(active, r['category']?.toString()))
        .toList();
  }
}
