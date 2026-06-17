import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection_category.dart';
import '../models/user_collection_type.dart';

const _prefsKeyV1 = 'category_hub_order_v1';
const _prefsKeyV2 = 'category_hub_order_v2';

/// Tuile du hub Collections (catégorie intégrée ou collection perso).
class HubTileEntry {
  final CollectionCategory? category;
  final UserCollectionType? customType;

  const HubTileEntry.category(this.category) : customType = null;
  const HubTileEntry.custom(this.customType) : category = null;

  String get storageKey => category != null
      ? 'c:${category!.dbValue}'
      : 'u:${customType!.id}';

  static HubTileEntry? fromStorageKey(
    String key, {
    required Map<String, CollectionCategory> categoriesByDb,
    required Map<String, UserCollectionType> customById,
  }) {
    if (key.startsWith('c:')) {
      final cat = categoriesByDb[key.substring(2)];
      return cat != null ? HubTileEntry.category(cat) : null;
    }
    if (key.startsWith('u:')) {
      final t = customById[key.substring(2)];
      return t != null ? HubTileEntry.custom(t) : null;
    }
    final cat = categoriesByDb[key];
    return cat != null ? HubTileEntry.category(cat) : null;
  }
}

/// Ordre personnalisé des tuiles sur l'écran « Collections ».
class CategoryHubOrder {
  static Future<List<HubTileEntry>> loadOrderedTiles(
    List<UserCollectionType> customTypes,
  ) async {
    final catsByDb = {
      for (final c in CollectionCategory.menuValues) c.dbValue: c,
    };
    final customById = {for (final t in customTypes) t.id: t};

    final prefs = await SharedPreferences.getInstance();
    var saved = prefs.getStringList(_prefsKeyV2);
    saved ??= prefs.getStringList(_prefsKeyV1);

    if (saved == null || saved.isEmpty) {
      return [
        ...CollectionCategory.menuValues.map(HubTileEntry.category),
        ...customTypes.map(HubTileEntry.custom),
      ];
    }

    final ordered = <HubTileEntry>[];
    final seen = <String>{};
    for (final key in saved) {
      final entry = HubTileEntry.fromStorageKey(
        key,
        categoriesByDb: catsByDb,
        customById: customById,
      );
      if (entry == null) continue;
      final sk = entry.storageKey;
      if (seen.contains(sk)) continue;
      seen.add(sk);
      ordered.add(entry);
    }
    for (final c in CollectionCategory.menuValues) {
      final e = HubTileEntry.category(c);
      if (!seen.contains(e.storageKey)) ordered.add(e);
    }
    for (final t in customTypes) {
      final e = HubTileEntry.custom(t);
      if (!seen.contains(e.storageKey)) ordered.add(e);
    }
    return ordered;
  }

  static Future<void> saveTileOrder(List<HubTileEntry> tiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKeyV2,
      tiles.map((e) => e.storageKey).toList(),
    );
  }
}
