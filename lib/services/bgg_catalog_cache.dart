import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ressource BGG mise en cache.
enum BggCacheKind {
  details('details'),
  expansions('expansions');

  const BggCacheKind(this.dbValue);
  final String dbValue;
}

class BggCacheEntry {
  final Object payload;
  final DateTime fetchedAt;

  const BggCacheEntry(this.payload, this.fetchedAt);

  bool isFresh(DateTime now, Duration ttl) => now.difference(fetchedAt) < ttl;
}

/// Stockage persistant (Supabase en prod, mémoire en test).
abstract class BggCacheStore {
  Future<BggCacheEntry?> read(String bggId, BggCacheKind kind);
  Future<void> write(String bggId, BggCacheKind kind, Object payload);
}

class SupabaseBggCacheStore implements BggCacheStore {
  static const _table = 'bgg_catalog_cache';

  @override
  Future<BggCacheEntry?> read(String bggId, BggCacheKind kind) async {
    final row = await Supabase.instance.client
        .from(_table)
        .select('payload, fetched_at')
        .eq('bgg_id', bggId)
        .eq('kind', kind.dbValue)
        .maybeSingle();
    if (row == null) return null;
    final at = DateTime.tryParse(row['fetched_at']?.toString() ?? '');
    final payload = row['payload'];
    if (at == null || payload == null) return null;
    return BggCacheEntry(payload as Object, at);
  }

  @override
  Future<void> write(String bggId, BggCacheKind kind, Object payload) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    await Supabase.instance.client.from(_table).upsert({
      'bgg_id': bggId,
      'kind': kind.dbValue,
      'payload': payload,
      'fetched_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

/// Cache BGG partagé : mémoire → table Supabase → API BGG.
///
/// - entrée fraîche (< [ttl]) : aucun appel BGG ;
/// - absente / périmée : un seul appel BGG même si plusieurs écrans
///   demandent le même jeu en même temps (requêtes en vol mutualisées) ;
/// - échec BGG : on renvoie l'entrée périmée si elle existe.
class BggCatalogCache {
  BggCatalogCache({
    BggCacheStore? store,
    this.ttl = const Duration(days: 14),
    DateTime Function()? clock,
  }) : _store = store ?? SupabaseBggCacheStore(),
       _clock = clock ?? DateTime.now;

  static final instance = BggCatalogCache();

  final BggCacheStore _store;
  final Duration ttl;
  final DateTime Function() _clock;

  final _memory = <String, BggCacheEntry>{};
  final _inFlight = <String, Future<Object?>>{};

  static String _key(String bggId, BggCacheKind kind) =>
      '${kind.dbValue}:$bggId';

  @visibleForTesting
  int get inFlightCount => _inFlight.length;

  /// [fetch] renvoie `null` si BGG n'a rien donné (non mis en cache).
  Future<Object?> getOrFetch(
    String bggId,
    BggCacheKind kind,
    Future<Object?> Function() fetch,
  ) {
    final id = bggId.trim();
    if (id.isEmpty) return Future.value(null);
    final key = _key(id, kind);

    final mem = _memory[key];
    if (mem != null && mem.isFresh(_clock(), ttl)) {
      return Future.value(mem.payload);
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _resolve(id, kind, key, fetch);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<Object?> _resolve(
    String id,
    BggCacheKind kind,
    String key,
    Future<Object?> Function() fetch,
  ) async {
    BggCacheEntry? stale = _memory[key];
    try {
      final stored = await _store.read(id, kind);
      if (stored != null) {
        if (stored.isFresh(_clock(), ttl)) {
          _memory[key] = stored;
          return stored.payload;
        }
        stale = stored;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BGG cache read $key: $e');
    }

    Object? fresh;
    try {
      fresh = await fetch();
    } catch (e) {
      if (stale != null) return stale.payload;
      rethrow;
    }
    if (fresh == null) return stale?.payload;

    _memory[key] = BggCacheEntry(fresh, _clock());
    try {
      await _store.write(id, kind, fresh);
    } catch (e) {
      if (kDebugMode) debugPrint('BGG cache write $key: $e');
    }
    return fresh;
  }

  @visibleForTesting
  void clearMemory() => _memory.clear();
}
