import 'dart:async';

import 'package:collection_app/models/bgg_expansion.dart';
import 'package:collection_app/services/bgg_catalog_cache.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements BggCacheStore {
  final rows = <String, BggCacheEntry>{};
  int reads = 0;
  int writes = 0;
  bool failReads = false;

  @override
  Future<BggCacheEntry?> read(String bggId, BggCacheKind kind) async {
    reads++;
    if (failReads) throw Exception('table absente');
    return rows['${kind.dbValue}:$bggId'];
  }

  @override
  Future<void> write(String bggId, BggCacheKind kind, Object payload) async {
    writes++;
    rows['${kind.dbValue}:$bggId'] = BggCacheEntry(payload, _now);
  }
}

var _now = DateTime(2026, 10, 15);

void main() {
  late _MemoryStore store;
  late BggCatalogCache cache;

  setUp(() {
    _now = DateTime(2026, 10, 15);
    store = _MemoryStore();
    cache = BggCatalogCache(store: store, clock: () => _now);
  });

  test('requêtes simultanées sur le même jeu → un seul appel BGG', () async {
    var calls = 0;
    final gate = Completer<Object?>();
    Future<Object?> fetch() {
      calls++;
      return gate.future;
    }

    final futures = [
      for (var i = 0; i < 5; i++)
        cache.getOrFetch('13', BggCacheKind.details, fetch),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(cache.inFlightCount, 1);
    gate.complete({'bgg_id': '13', 'image_url': 'https://img/catan.jpg'});
    final results = await Future.wait(futures);

    expect(calls, 1);
    expect(store.writes, 1);
    for (final r in results) {
      expect((r as Map)['bgg_id'], '13');
    }
    expect(cache.inFlightCount, 0);
  });

  test('jeux / types différents ne sont pas mutualisés', () async {
    var calls = 0;
    Future<Object?> fetch() async {
      calls++;
      return {'n': calls};
    }

    await Future.wait([
      cache.getOrFetch('1', BggCacheKind.details, fetch),
      cache.getOrFetch('2', BggCacheKind.details, fetch),
      cache.getOrFetch('1', BggCacheKind.expansions, fetch),
    ]);
    expect(calls, 3);
  });

  test('entrée Supabase fraîche (< 30 j) : aucun appel BGG', () async {
    store.rows['details:13'] = BggCacheEntry({
      'bgg_id': '13',
      'from': 'cache',
    }, _now.subtract(const Duration(days: 29)));
    var calls = 0;
    final r = await cache.getOrFetch('13', BggCacheKind.details, () async {
      calls++;
      return {'from': 'bgg'};
    });
    expect(calls, 0);
    expect((r as Map)['from'], 'cache');
  });

  test('entrée périmée (> 30 j) : rafraîchie depuis BGG et réécrite', () async {
    store.rows['details:13'] = BggCacheEntry({
      'from': 'old',
    }, _now.subtract(const Duration(days: 31)));
    final r = await cache.getOrFetch(
      '13',
      BggCacheKind.details,
      () async => {'from': 'bgg'},
    );
    expect((r as Map)['from'], 'bgg');
    expect(store.writes, 1);
    expect((store.rows['details:13']!.payload as Map)['from'], 'bgg');
  });

  test('échec BGG : on sert la version périmée plutôt que rien', () async {
    store.rows['details:13'] = BggCacheEntry({
      'from': 'old',
    }, _now.subtract(const Duration(days: 60)));
    final r = await cache.getOrFetch(
      '13',
      BggCacheKind.details,
      () async => throw Exception('429'),
    );
    expect((r as Map)['from'], 'old');
  });

  test(
    'échec BGG sans cache : l\'erreur remonte et rien n\'est figé',
    () async {
      await expectLater(
        cache.getOrFetch(
          '9',
          BggCacheKind.details,
          () async => throw Exception('429'),
        ),
        throwsException,
      );
      expect(cache.inFlightCount, 0);
      final r = await cache.getOrFetch(
        '9',
        BggCacheKind.details,
        () async => {'ok': true},
      );
      expect((r as Map)['ok'], isTrue);
    },
  );

  test('réponse vide (null) : pas mise en cache', () async {
    final r = await cache.getOrFetch(
      '5',
      BggCacheKind.details,
      () async => null,
    );
    expect(r, isNull);
    expect(store.writes, 0);
  });

  test('cache mémoire : 2e appel ne relit pas Supabase', () async {
    await cache.getOrFetch('13', BggCacheKind.details, () async => {'a': 1});
    final readsAfterFirst = store.reads;
    await cache.getOrFetch('13', BggCacheKind.details, () async => {'a': 2});
    expect(store.reads, readsAfterFirst);
  });

  test('mémoire périmée après 30 jours → nouvel appel', () async {
    var calls = 0;
    Future<Object?> fetch() async => {'n': ++calls};
    await cache.getOrFetch('13', BggCacheKind.details, fetch);
    _now = _now.add(const Duration(days: 31));
    final r = await cache.getOrFetch('13', BggCacheKind.details, fetch);
    expect(calls, 2);
    expect((r as Map)['n'], 2);
  });

  test('table Supabase indisponible : on passe directement par BGG', () async {
    store.failReads = true;
    final r = await cache.getOrFetch(
      '13',
      BggCacheKind.details,
      () async => {'ok': 1},
    );
    expect((r as Map)['ok'], 1);
  });

  test('extensions : sérialisation aller-retour', () {
    const exp = BggExpansion(
      bggId: '926',
      title: 'Catan: Seafarers',
      imageUrl: 'https://img/sea.jpg',
      year: 1997,
      bggRank: 300,
      avgRating: 7.1,
    );
    final back = BggExpansion.fromJson(exp.toJson());
    expect(back.bggId, '926');
    expect(back.title, 'Catan: Seafarers');
    expect(back.year, 1997);
    expect(back.bggRank, 300);
    expect(back.avgRating, 7.1);
    expect(back.summary, isNull);
  });
}
