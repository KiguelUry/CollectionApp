import 'dart:async';

import 'package:collection_app/services/bgg_collection_import_service.dart';
import 'package:collection_app/services/bgg_service.dart';
import 'package:collection_app/utils/bgg_collection_parse.dart';
import 'package:collection_app/widgets/bgg_collection_import_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('saisie du pseudo → barre de progression → résumé', (
    tester,
  ) async {
    final fetchGate = Completer<BggCollectionFetchResult>();
    final insertGate = Completer<void>();
    String? requested;
    final service = BggCollectionImportService(
      batchSize: 2,
      fetchCollection: (user, _) {
        requested = user;
        return fetchGate.future;
      },
      loadOwned: () async => const OwnedBoardgames(),
      insertBatch: (b) async {
        if (b.first.bggId == '3') await insertGate.future;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BggCollectionImportCard(service: service, initialUsername: ''),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('bgg_import_progress')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('bgg_username_field')),
      'kilian',
    );
    await tester.tap(find.byKey(const ValueKey('bgg_import_button')));
    await tester.pump();

    expect(requested, 'kilian');
    final indeterminate = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('bgg_import_progress')),
    );
    expect(indeterminate.value, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('bgg_import_button')))
          .onPressed,
      isNull,
    );

    fetchGate.complete(
      const BggCollectionFetchResult.ok([
        BggCollectionEntry(bggId: '1', title: 'A'),
        BggCollectionEntry(bggId: '2', title: 'B'),
        BggCollectionEntry(bggId: '3', title: 'C'),
      ]),
    );
    await tester.pump();
    await tester.pump();

    final mid = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('bgg_import_progress')),
    );
    expect(mid.value, closeTo(2 / 3, 0.001));
    expect(find.text('2 / 3'), findsOneWidget);

    insertGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('3 jeux importés'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('bgg_import_progress')),
          )
          .value,
      1.0,
    );
  });

  testWidgets('erreur BGG affichée', (tester) async {
    final service = BggCollectionImportService(
      fetchCollection: (_, _) async =>
          const BggCollectionFetchResult.error('Invalid username specified'),
      loadOwned: () async => const OwnedBoardgames(),
      insertBatch: (_) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BggCollectionImportCard(
            service: service,
            initialUsername: 'zz',
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('bgg_import_button')));
    await tester.pumpAndSettle();
    expect(find.text('Invalid username specified'), findsOneWidget);
    expect(find.byKey(const ValueKey('bgg_import_progress')), findsNothing);
  });
}
