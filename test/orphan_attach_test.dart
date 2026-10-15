import 'package:collection_app/models/boardgame_play_session.dart';
import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/services/global_play_history_service.dart';
import 'package:collection_app/widgets/orphan_attach_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CollectionItem _game(String id, String title, {String? bggId}) =>
    CollectionItem(
      id: id,
      title: title,
      category: CollectionCategory.boardgame,
      isWishlist: false,
      metadata: {'bgg_id': ?bggId},
    );

BoardgamePlaySession _session(DateTime date) =>
    BoardgamePlaySession(date: date, players: const ['A', 'B']);

void main() {
  group('mergeSessionIntoHistory', () {
    test('insère et retrie du plus récent au plus ancien', () {
      final history = [
        _session(DateTime(2026, 3, 10)),
        _session(DateTime(2026, 1, 5)),
      ];
      final merged =
          mergeSessionIntoHistory(history, _session(DateTime(2026, 2, 1)));
      expect(merged.map((s) => s.date).toList(), [
        DateTime(2026, 3, 10),
        DateTime(2026, 2, 1),
        DateTime(2026, 1, 5),
      ]);
    });

    test('historique vide → une seule partie', () {
      final merged = mergeSessionIntoHistory(
        const [],
        _session(DateTime(2026, 4, 1)),
      );
      expect(merged.length, 1);
    });
  });

  group('rankOrphanAttachCandidates', () {
    final items = [
      _game('1', 'Zombicide'),
      _game('2', 'Azul'),
      _game('3', 'Catan : Extension', bggId: '13'),
      _game('4', 'Catan'),
    ];

    test('même BGG id en premier, puis titre exact, puis proche', () {
      final ranked = rankOrphanAttachCandidates(
        items,
        orphanTitle: 'catan',
        orphanBggId: '13',
      );
      expect(ranked.map((i) => i.id).toList(), ['3', '4', '2', '1']);
    });

    test('sans BGG id : titre exact d\'abord, reste alphabétique', () {
      final ranked = rankOrphanAttachCandidates(items, orphanTitle: 'Azul');
      expect(ranked.first.id, '2');
      expect(ranked.length, items.length);
    });
  });

  testWidgets('OrphanAttachSheet filtre et renvoie le jeu choisi',
      (tester) async {
    CollectionItem? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<CollectionItem>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => OrphanAttachSheet(
                      orphanTitle: 'Catan',
                      candidates: [_game('1', 'Azul'), _game('2', 'Catan')],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Rattacher « Catan »'), findsOneWidget);
    expect(find.text('Azul'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'cat');
    await tester.pump();
    expect(find.text('Azul'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'Catan'));
    await tester.pumpAndSettle();
    expect(picked?.id, '2');
  });
}
