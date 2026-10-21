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

  /// Une seule requête SQL groupée (`.inFilter`) — obligatoire pour Découvrir.
  Future<Map<String, BggCacheEntry>> readMany(
    List<String> bggIds,
    BggCacheKind kind,
  );

  /// Upsert groupé des payloads (clé = bgg_id).
  Future<void> writeMany(
    Map<String, Object> payloadsById,
    BggCacheKind kind,
  );
}

/// Coupe-circuit : si la table est absente (404) ou invalide (400),
/// on arrête les appels PostgREST pour [cooldown] (évite 70+ erreurs au scroll).
class _CatalogCacheBreaker {
  static bool tripped = false;
  static DateTime? trippedAt;
  static const cooldown = Duration(minutes: 15);

  static bool get isOpen {
    if (!tripped) return false;
    final at = trippedAt;
    if (at != null && DateTime.now().difference(at) > cooldown) {
      tripped = false;
      trippedAt = null;
      return false;
    }
    return true;
  }

  static void trip([Object? error]) {
    if (tripped) return;
    tripped = true;
    trippedAt = DateTime.now();
    if (kDebugMode) {
      debugPrint(
        'BGG catalog cache OFF (${cooldown.inMinutes} min) : $error',
      );
    }
  }

  static bool looksLikeSchemaError(Object e) {
    if (e is PostgrestException) {
      final code = (e.code ?? '').toUpperCase();
      // PGRST205 = table introuvable, 42P01 = undefined_table, 42703 = undefined_column
      if (code == 'PGRST205' ||
          code == '42P01' ||
          code == '42703' ||
          code == 'PGRST204') {
        return true;
      }
      final status = e.message; // souvent contient "404" / "relation … does not exist"
      final lower = '${e.code} $status ${e.details} ${e.hint}'.toLowerCase();
      if (lower.contains('404') ||
          lower.contains('does not exist') ||
          lower.contains('bgg_catalog_cache') && lower.contains('schema cache')) {
        return true;
      }
    }
    final text = e.toString().toLowerCase();
    return text.contains('bgg_catalog_cache') &&
        (text.contains('404') ||
            text.contains('400') ||
            text.contains('does not exist') ||
            text.contains('pgrst205') ||
            text.contains('schema cache'));
  }
}

class SupabaseBggCacheStore implements BggCacheStore {
  static const _table = 'bgg_catalog_cache';

  @override
  Future<BggCacheEntry?> read(String bggId, BggCacheKind kind) async {
    if (_CatalogCacheBreaker.isOpen) return null;
    try {
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
    } catch (e) {
      if (_CatalogCacheBreaker.looksLikeSchemaError(e)) {
        _CatalogCacheBreaker.trip(e);
      } else if (kDebugMode) {
        debugPrint('BGG cache read: $e');
      }
      return null;
    }
  }

  @override
  Future<void> write(String bggId, BggCacheKind kind, Object payload) async {
    await writeMany({bggId: payload}, kind);
  }

  @override
  Future<Map<String, BggCacheEntry>> readMany(
    List<String> bggIds,
    BggCacheKind kind,
  ) async {
    final out = <String, BggCacheEntry>{};
    final ids = bggIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty || _CatalogCacheBreaker.isOpen) return out;
    try {
      final rows = await Supabase.instance.client
          .from(_table)
          .select('bgg_id, payload, fetched_at')
          .inFilter('bgg_id', ids)
          .eq('kind', kind.dbValue);
      for (final row in rows as List) {
        if (row is! Map) continue;
        final id = row['bgg_id']?.toString();
        final at = DateTime.tryParse(row['fetched_at']?.toString() ?? '');
        final payload = row['payload'];
        if (id == null || id.isEmpty || at == null || payload == null) continue;
        out[id] = BggCacheEntry(payload as Object, at);
      }
    } catch (e) {
      if (_CatalogCacheBreaker.looksLikeSchemaError(e)) {
        _CatalogCacheBreaker.trip(e);
      } else if (kDebugMode) {
        debugPrint('BGG cache readMany: $e');
      }
    }
    return out;
  }

  @override
  Future<void> writeMany(
    Map<String, Object> payloadsById,
    BggCacheKind kind,
  ) async {
    if (payloadsById.isEmpty || _CatalogCacheBreaker.isOpen) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = [
      for (final e in payloadsById.entries)
        if (e.key.trim().isNotEmpty)
          {
            'bgg_id': e.key.trim(),
            'kind': kind.dbValue,
            'payload': e.value,
            'fetched_at': now,
          },
    ];
    if (rows.isEmpty) return;
    try {
      await Supabase.instance.client.from(_table).upsert(rows);
    } catch (e) {
      if (_CatalogCacheBreaker.looksLikeSchemaError(e)) {
        _CatalogCacheBreaker.trip(e);
      } else if (kDebugMode) {
        debugPrint('BGG cache writeMany: $e');
      }
    }
  }
}

/// Cache BGG partagé : mémoire → table Supabase → API BGG.
///
/// - entrée fraîche (< [ttl]) : aucun appel BGG ;
/// - absente / périmée : un seul appel BGG même si plusieurs écrans
///   demandent le même jeu en même temps (requêtes en vol mutualisées) ;
/// - table absente (404) : coupe-circuit, mémoire + BGG uniquement ;
/// - échec BGG : on renvoie l'entrée périmée si elle existe.
class BggCatalogCache {
  BggCatalogCache({
    BggCacheStore? store,
    this.ttl = const Duration(days: 30),
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

  /// Lecture synchrone du cache mémoire (aucun appel réseau).
  Object? peekFresh(String bggId, BggCacheKind kind) {
    final mem = _memory[_key(bggId.trim(), kind)];
    if (mem != null && mem.isFresh(_clock(), ttl)) return mem.payload;
    return null;
  }

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

  /// Vide le cache mémoire (ex. epoch Découvrir `discover_cache_v4`).
  void clearMemory() => _memory.clear();

  @visibleForTesting
  static void resetCircuitBreaker() {
    _CatalogCacheBreaker.tripped = false;
    _CatalogCacheBreaker.trippedAt = null;
  }

  /// Lecture groupée mémoire → **1** SELECT Supabase `.inFilter` → Map par bgg_id.
  /// Entrées sans `title` ou sans `image_url` sont traitées comme absentes (v4).
  Future<Map<String, Object>> readManyFresh(
    List<String> bggIds,
    BggCacheKind kind,
  ) async {
    final out = <String, Object>{};
    final missing = <String>[];
    final now = _clock();
    for (final raw in bggIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      final mem = _memory[_key(id, kind)];
      if (mem != null && mem.isFresh(now, ttl) && _payloadUsable(mem.payload)) {
        out[id] = mem.payload;
      } else {
        missing.add(id);
      }
    }
    if (missing.isEmpty) return out;

    try {
      final stored = await _store.readMany(missing, kind);
      for (final e in stored.entries) {
        if (!e.value.isFresh(now, ttl) || !_payloadUsable(e.value.payload)) {
          continue;
        }
        _memory[_key(e.key, kind)] = e.value;
        out[e.key] = e.value.payload;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BGG cache readManyFresh: $e');
    }
    return out;
  }

  /// Écriture mémoire + **1** upsert Supabase groupé.
  Future<void> writeManyFresh(
    Map<String, Object> payloadsById,
    BggCacheKind kind,
  ) async {
    if (payloadsById.isEmpty) return;
    final now = _clock();
    for (final e in payloadsById.entries) {
      final id = e.key.trim();
      if (id.isEmpty || !_payloadUsable(e.value)) continue;
      _memory[_key(id, kind)] = BggCacheEntry(e.value, now);
    }
    try {
      await _store.writeMany(payloadsById, kind);
    } catch (e) {
      if (kDebugMode) debugPrint('BGG cache writeManyFresh: $e');
    }
  }

  /// Payload Découvrir / fiches : titre + image obligatoires (purge des vieux caches).
  static bool _payloadUsable(Object payload) {
    if (payload is! Map) return false;
    final title = payload['title']?.toString().trim() ?? '';
    final image = payload['image_url']?.toString().trim() ?? '';
    return title.isNotEmpty && image.isNotEmpty;
  }
}

/// Résultats de recherche BGG partagés entre utilisateurs (`bgg_search_cache`).
/// Table optionnelle : toute erreur (table absente, hors ligne) est ignorée.
class BggSearchSharedCache {
  static const _table = 'bgg_search_cache';
  static const ttl = Duration(days: 7);

  static String normalizeKey(String key) =>
      key.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Renvoie les jeux et leur fraîcheur, ou `null` si absent.
  static Future<({List<Map<String, String>> games, bool fresh})?> read(
    String key,
  ) async {
    try {
      final row = await Supabase.instance.client
          .from(_table)
          .select('payload, fetched_at')
          .eq('query_key', normalizeKey(key))
          .maybeSingle();
      if (row == null || row['payload'] is! List) return null;
      final at = DateTime.tryParse(row['fetched_at']?.toString() ?? '');
      final games = [
        for (final g in row['payload'] as List)
          if (g is Map)
            {
              for (final e in g.entries)
                if (e.value != null) e.key.toString(): e.value.toString(),
            },
      ];
      if (games.isEmpty) return null;
      final fresh = at != null && DateTime.now().difference(at) < ttl;
      return (games: games, fresh: fresh);
    } catch (e) {
      if (kDebugMode) debugPrint('BGG search cache read: $e');
      return null;
    }
  }

  static Future<void> write(
    String key,
    List<Map<String, String>> games,
  ) async {
    if (games.isEmpty) return;
    try {
      if (Supabase.instance.client.auth.currentUser == null) return;
      await Supabase.instance.client.from(_table).upsert({
        'query_key': normalizeKey(key),
        'payload': games,
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('BGG search cache write: $e');
    }
  }
}
