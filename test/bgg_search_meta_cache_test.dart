import 'package:collection_app/services/bgg_catalog_cache.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemStore implements BggCacheStore {
  final rows = <String, BggCacheEntry>{};
  @override
  Future<BggCacheEntry?> read(String bggId, BggCacheKind kind) async =>
      rows['${kind.dbValue}:$bggId'];

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
    for (final id in bggIds) {
      final e = rows['${kind.dbValue}:$id'];
      if (e != null) out[id] = e;
    }
    return out;
  }

  @override
  Future<void> writeMany(
    Map<String, Object> payloadsById,
    BggCacheKind kind,
  ) async {
    final now = DateTime.now();
    for (final e in payloadsById.entries) {
      rows['${kind.dbValue}:${e.key}'] = BggCacheEntry(e.value, now);
    }
  }
}

void main() {
  test('enrichissement recherche : 2 appels meta → 1 fetch BGG', () async {
    var fetches = 0;
    final cache = BggCatalogCache(store: _MemStore());
    Future<Object?> metaFetch(String id) async {
      fetches++;
      return {
        'bgg_id': id,
        'bgg_avg_rating': 8.1,
        'bgg_search_meta_rank': 42,
        'image_url': 'https://img/$id.jpg',
      };
    }

    await cache.getOrFetch('13', BggCacheKind.details, () => metaFetch('13'));
    await cache.getOrFetch('13', BggCacheKind.details, () => metaFetch('13'));
    expect(fetches, 1);
  });
}
