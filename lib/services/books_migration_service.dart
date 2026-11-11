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

  static Future<int>? _inFlight;

  /// Dédup séries + tomes + rattachement orphelins. Idempotent.
  /// Un second appel concurrent attend la même passe.
  static Future<int> runIfNeeded({bool force = false}) {
    if (!force && _inFlight != null) return _inFlight!;
    final run = _run(force);
    if (!force) {
      _inFlight = run;
      run.whenComplete(() {
        if (identical(_inFlight, run)) _inFlight = null;
      });
    }
    return run;
  }

  static Future<int> _run(bool force) async {
    if (!force && await isDone()) return 0;
    final service = BookSeriesService();
    final bundle = await service.fetchCollectionBundle();
    var n = 0;
    n += await service.ensureStandaloneSeriesForUnassigned();
    n += await service.dedupeDuplicateSeriesFolders();
    for (final s in bundle.series) {
      n += await service.dedupeVolumeItems(
        s.id,
        knownItems: bundle.itemsBySeries[s.id] ?? const [],
      );
    }
    BooksCollectionCache.instance.clear();
    await markDone();
    return n;
  }
}
