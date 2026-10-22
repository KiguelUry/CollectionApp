import 'package:shared_preferences/shared_preferences.dart';

import 'book_series_service.dart';
import 'books_collection_cache.dart';

/// Migration Livres v3 — une seule fois (flag SharedPreferences).
abstract final class BooksMigrationService {
  static const prefKey = 'books_migration_v3_done';

  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefKey) == true;
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, true);
  }

  /// Force une nouvelle passe (menu debug / nettoyage).
  static Future<void> resetFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefKey);
  }

  /// Dédup séries + tomes + rattachement orphelins. Idempotent.
  static Future<int> runIfNeeded({bool force = false}) async {
    if (!force && await isDone()) return 0;
    final service = BookSeriesService();
    var n = 0;
    n += await service.ensureStandaloneSeriesForUnassigned();
    n += await service.dedupeDuplicateSeriesFolders();
    final all = await service.fetchAllRootSeries();
    for (final s in all) {
      n += await service.dedupeVolumeItems(s.id);
    }
    BooksCollectionCache.instance.clear();
    await markDone();
    return n;
  }
}
