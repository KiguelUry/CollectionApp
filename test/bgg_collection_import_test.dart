import 'dart:async';

import 'package:collection_app/services/bgg_collection_import_service.dart';
import 'package:collection_app/services/bgg_service.dart';
import 'package:collection_app/utils/bgg_collection_parse.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _xml = '''<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<items totalitems="3" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
  <item objecttype="thing" objectid="13" subtype="boardgame" collid="1">
    <name sortindex="1">Catan</name>
    <yearpublished>1995</yearpublished>
    <image>https://cf.geekdo-images.com/catan.jpg</image>
    <thumbnail>//cf.geekdo-images.com/catan_t.jpg</thumbnail>
    <stats minplayers="3" maxplayers="4" minplaytime="60" maxplaytime="120" playingtime="120" numowned="1">
      <rating value="8"/>
    </stats>
    <status own="1"/>
    <numplays>4</numplays>
  </item>
  <item objecttype="thing" objectid="926" subtype="boardgameexpansion" collid="2">
    <name sortindex="1">Catan: Seafarers</name>
    <stats minplayers="3" maxplayers="4" playingtime="0"/>
  </item>
  <item objecttype="thing" objectid="230802" subtype="boardgame" collid="3">
    <name sortindex="1">Azul</name>
    <stats minplayers="2" maxplayers="4" playingtime="45"/>
  </item>
  <item objecttype="thing" objectid="13" subtype="boardgame" collid="4">
    <name sortindex="1">Catan</name>
  </item>
</items>''';

List<BggCollectionEntry> _entries(int n) => [
  for (var i = 0; i < n; i++)
    BggCollectionEntry(bggId: '${1000 + i}', title: 'Jeu $i'),
];

void main() {
  group('parse XML collection', () {
    test('jeux, extensions, images, dédoublonnage', () {
      final list = parseBggCollectionXml(_xml);
      expect(list.map((e) => e.bggId), ['13', '926', '230802']);
      final catan = list.first;
      expect(catan.title, 'Catan');
      expect(catan.year, 1995);
      expect(catan.imageUrl, 'https://cf.geekdo-images.com/catan.jpg');
      expect(catan.thumbnailUrl, 'https://cf.geekdo-images.com/catan_t.jpg');
      expect(catan.minPlayers, 3);
      expect(catan.maxPlayers, 4);
      expect(catan.playingTime, 120);
      expect(list[1].isExpansion, isTrue);
      expect(list[1].playingTime, isNull);
    });

    test('erreur pseudo et file d\'attente BGG', () {
      expect(
        bggCollectionXmlError(
          '<errors><error><message>Invalid username specified</message></error></errors>',
        ),
        'Invalid username specified',
      );
      expect(bggCollectionXmlError(_xml), isNull);
      expect(isBggCollectionPending(202, ''), isTrue);
      expect(
        isBggCollectionPending(
          200,
          '<message>Please try again later for access.</message>',
        ),
        isTrue,
      );
      expect(isBggCollectionPending(200, _xml), isFalse);
      expect(parseBggCollectionXml('pas du xml'), isEmpty);
    });

    test('JSON edge function', () {
      final e = BggCollectionEntry.fromJson({
        'bgg_id': '13',
        'title': 'Catan',
        'year': 1995,
        'image_url': '//img/c.jpg',
        'min_players': 3,
        'is_expansion': false,
      });
      expect(e.imageUrl, 'https://img/c.jpg');
      expect(e.minPlayers, 3);
    });
  });

  group('plan d\'import', () {
    test('ignore déjà possédés (id ou titre) et extensions', () {
      final plan = planBggImport(
        parseBggCollectionXml(_xml),
        existingBggIds: {'13'},
        existingTitles: const [],
      );
      expect(plan.toInsert.map((e) => e.title), ['Azul']);
      expect(plan.alreadyOwned.map((e) => e.title), ['Catan']);
      expect(plan.skippedExpansions.single.bggId, '926');

      final byTitle = planBggImport(
        parseBggCollectionXml(_xml),
        existingTitles: const ['  AZUL '],
      );
      expect(byTitle.toInsert.map((e) => e.title), ['Catan']);
    });

    test('objet collection : boardgame possédé avec bgg_id', () {
      final item = collectionItemFromBggEntry(
        parseBggCollectionXml(_xml).first,
        userId: 'me',
      );
      expect(item.metadata!['bgg_id'], '13');
      expect(item.metadata!['year_published'], 1995);
      expect(item.metadata!['imported_from_bgg'], isTrue);
      expect(item.isWishlist, isFalse);
      final json = item.toInsertJson(
        isWishlist: false,
        locationUserId: 'me',
        addedBy: 'me',
      );
      expect(json['category'], 'boardgame');
      expect(json['location_user_id'], 'me');
      expect(json['min_players'], 3);
      expect(json['playing_time'], 120);
    });
  });

  group('service d\'import (fond + progression)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('import par lots avec progression jusqu\'à 100 %', () async {
      final batches = <int>[];
      final service = BggCollectionImportService(
        batchSize: 20,
        fetchCollection: (_, _) async =>
            BggCollectionFetchResult.ok(_entries(45)),
        loadOwned: () async => const OwnedBoardgames(bggIds: {'1000'}),
        insertBatch: (b) async => batches.add(b.length),
      );
      final fractions = <double?>[];
      service.progress.addListener(
        () => fractions.add(service.progress.value.fraction),
      );

      final result = await service.start('kilian');
      expect(result.phase, BggImportPhase.done);
      expect(result.inserted, 44);
      expect(result.alreadyOwned, 1);
      expect(batches, [20, 20, 4]);
      expect(fractions.whereType<double>().last, 1.0);
      expect(
        fractions.whereType<double>().toList(),
        orderedEquals([...fractions.whereType<double>()]..sort()),
      );
      expect(result.message, '44 jeux importés · 1 déjà présent');
      expect(await BggCollectionImportService.savedUsername(), 'kilian');
    });

    test('pseudo invalide → erreur sans insertion', () async {
      var inserted = 0;
      final service = BggCollectionImportService(
        fetchCollection: (_, _) async =>
            const BggCollectionFetchResult.error('Invalid username specified'),
        loadOwned: () async => const OwnedBoardgames(),
        insertBatch: (b) async => inserted += b.length,
      );
      final r = await service.start('zzz');
      expect(r.phase, BggImportPhase.error);
      expect(r.message, 'Invalid username specified');
      expect(inserted, 0);
    });

    test('pseudo vide', () async {
      final service = BggCollectionImportService(
        fetchCollection: (_, _) async =>
            throw StateError('ne doit pas être appelé'),
        loadOwned: () async => const OwnedBoardgames(),
        insertBatch: (_) async {},
      );
      final r = await service.start('   ');
      expect(r.phase, BggImportPhase.error);
    });

    test('double clic : un seul import en cours', () async {
      var fetches = 0;
      final gate = Completer<BggCollectionFetchResult>();
      final service = BggCollectionImportService(
        fetchCollection: (_, onStatus) {
          fetches++;
          onStatus('BGG prépare la collection… (1/9)');
          return gate.future;
        },
        loadOwned: () async => const OwnedBoardgames(),
        insertBatch: (_) async {},
      );
      final a = service.start('kilian');
      final b = service.start('kilian');
      expect(service.progress.value.isRunning, isTrue);
      expect(
        service.progress.value.message,
        'BGG prépare la collection… (1/9)',
      );
      expect(service.progress.value.fraction, isNull);
      gate.complete(BggCollectionFetchResult.ok(_entries(2)));
      final results = await Future.wait([a, b]);
      expect(fetches, 1);
      expect(identical(results[0], results[1]), isTrue);
    });

    test('erreur réseau pendant l\'insertion → phase erreur', () async {
      final service = BggCollectionImportService(
        fetchCollection: (_, _) async =>
            BggCollectionFetchResult.ok(_entries(30)),
        loadOwned: () async => const OwnedBoardgames(),
        insertBatch: (b) async {
          if (b.first.bggId == '1020') throw Exception('offline');
        },
      );
      final r = await service.start('kilian');
      expect(r.phase, BggImportPhase.error);
      expect(r.inserted, 20);
      expect(r.message, contains('offline'));
    });
  });
}
