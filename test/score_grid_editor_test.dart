import 'dart:math';

import 'package:collection_app/models/boardgame_score_grid.dart';
import 'package:collection_app/widgets/boardgame_score_grid_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _grid = BoardgameScoreGrid(
  players: ['Alice', 'Bob', 'Chloé'],
  rounds: [
    BoardgameScoreRound(label: 'Tour 1', scores: [null, null, null]),
  ],
  playerColors: [0, 1, 2],
);

Future<GlobalKey<BoardgameScoreGridEditorState>> _pump(
  WidgetTester tester, {
  Future<String?> Function()? onPickPlayer,
  Random? random,
  BoardgameScoreGrid grid = _grid,
  Size size = const Size(1200, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<BoardgameScoreGridEditorState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BoardgameScoreGridEditor(
            key: key,
            initialGrid: grid,
            onPickPlayer: onPickPlayer,
            random: random,
          ),
        ),
      ),
    ),
  );
  return key;
}

Future<void> _drawFirst(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('who_starts')));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('« Qui commence ? » marque un 1er joueur dans la grille',
      (tester) async {
    final key = await _pump(tester, random: Random(7));
    expect(find.text('🎲 Qui commence ?'), findsOneWidget);
    expect(find.text(kFirstPlayerBadge), findsNothing);

    await _drawFirst(tester);

    final first = key.currentState!.firstPlayerIndex;
    expect(first, isNotNull);
    expect(find.byType(FirstPlayerBadge), findsOneWidget);
    final name = _grid.players[first!];
    expect(find.textContaining('$name  $kFirstPlayerBadge'), findsOneWidget);
    expect(find.textContaining('$name commence'), findsOneWidget);
  });

  testWidgets('le badge suit le joueur et disparaît s\'il est retiré',
      (tester) async {
    final key = await _pump(tester, random: Random(1));
    await _drawFirst(tester);
    final first = key.currentState!.firstPlayerIndex!;
    final name = _grid.players[first];

    final chip = find.ancestor(
      of: find.textContaining('$name  $kFirstPlayerBadge'),
      matching: find.byType(InputChip),
    );
    expect(chip, findsOneWidget);
    tester.widget<InputChip>(chip).onDeleted!();
    await tester.pump();
    expect(key.currentState!.firstPlayerIndex, isNull);
    expect(find.byType(FirstPlayerBadge), findsNothing);
  });

  testWidgets('sans joueur : message au lieu d\'un tirage', (tester) async {
    await _pump(
      tester,
      grid: const BoardgameScoreGrid(players: [], rounds: []),
    );
    await tester.tap(find.byKey(const ValueKey('who_starts')));
    await tester.pump();
    expect(find.text('Ajoute d\'abord des joueurs.'), findsOneWidget);
  });

  testWidgets('« Depuis mes contacts » est dans la modale, plus à côté du Shuffle',
      (tester) async {
    await _pump(tester, onPickPlayer: () async => 'Lou');

    expect(find.byTooltip('Depuis mes contacts'), findsNothing);
    expect(find.byTooltip('Mélanger'), findsOneWidget);

    await tester.tap(find.text('Ajouter un joueur'));
    await tester.pumpAndSettle();

    final suffix = find.byKey(const ValueKey('pick_from_contacts'));
    expect(suffix, findsOneWidget);
    final field = find.ancestor(of: suffix, matching: find.byType(TextField));
    expect(field, findsOneWidget);

    await tester.tap(suffix);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contacts enregistrés'));
    await tester.pumpAndSettle();
    final tf = tester.widget<TextField>(field);
    expect(tf.controller!.text, 'Lou');
  });

  testWidgets('pas de bouton contacts sans source de contacts',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Ajouter un joueur'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick_from_contacts')), findsNothing);
  });

  testWidgets('colonnes plus larges sur PC que sur mobile', (tester) async {
    await _pump(tester);
    final wide = tester.getSize(
      find
          .ancestor(of: find.text('Bob').last, matching: find.byType(AnimatedContainer))
          .first,
    );

    await _pump(tester, size: const Size(390, 1600));
    final narrow = tester.getSize(
      find
          .ancestor(of: find.text('Bob').last, matching: find.byType(AnimatedContainer))
          .first,
    );
    expect(wide.width, greaterThanOrEqualTo(112));
    expect(narrow.width, lessThan(wide.width));
  });
}
