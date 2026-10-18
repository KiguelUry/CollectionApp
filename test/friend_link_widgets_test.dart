import 'package:collection_app/models/boardgame_score_grid.dart';
import 'package:collection_app/models/friend_choice.dart';
import 'package:collection_app/widgets/boardgame_score_grid_editor.dart';
import 'package:collection_app/widgets/friend_link_selector.dart';
import 'package:collection_app/widgets/recommend_to_friend_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _friends = [
  FriendChoice(profileId: 'p_igor', username: 'igor42'),
  FriendChoice(profileId: 'p_lou', username: 'loulou'),
];

Future<void> _pumpEditor(
  WidgetTester tester, {
  List<FriendChoice> friends = _friends,
  void Function(String, FriendChoice)? onLinked,
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BoardgameScoreGridEditor(
            initialGrid: const BoardgameScoreGrid(
              players: ['Kiki'],
              rounds: [
                BoardgameScoreRound(scores: [null]),
              ],
            ),
            friendChoices: friends,
            onFriendLinked: onLinked,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('« Ajouter un joueur » : lien ami', () {
    testWidgets('cocher + choisir un ami lie le joueur ajouté', (tester) async {
      String? linkedName;
      FriendChoice? linkedFriend;
      await _pumpEditor(
        tester,
        onLinked: (name, f) {
          linkedName = name;
          linkedFriend = f;
        },
      );
      await tester.tap(find.text('Ajouter un joueur'));
      await tester.pumpAndSettle();

      expect(
        find.text('Cette personne est dans ma liste d\'amis'),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('pick_from_contacts')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('igor42'));
      await tester.pumpAndSettle();

      final nameField = find.widgetWithText(TextField, 'Nom');
      expect(tester.widget<TextField>(nameField).controller!.text, 'igor42');
      await tester.enterText(nameField, 'Igor');
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();

      expect(linkedName, 'Igor');
      expect(linkedFriend!.profileId, 'p_igor');
      expect(find.text('Igor'), findsWidgets);
    });

    testWidgets('sans cocher : aucun lien', (tester) async {
      var calls = 0;
      await _pumpEditor(tester, onLinked: (_, _) => calls++);
      await tester.tap(find.text('Ajouter un joueur'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'Lou');
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });

    testWidgets('pas d\'amis : pas de case', (tester) async {
      await _pumpEditor(tester, friends: const []);
      await tester.tap(find.text('Ajouter un joueur'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick_from_contacts')), findsNothing);
    });
  });

  testWidgets('FriendLinkSelector décoché → sélection effacée', (tester) async {
    var linked = true;
    FriendChoice? selected = _friends.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FriendLinkSelector(
              friends: _friends,
              linked: linked,
              selected: selected,
              onLinkedChanged: (v) => setState(() {
                linked = v;
                if (!v) selected = null;
              }),
              onSelected: (f) => setState(() => selected = f),
            ),
          ),
        ),
      ),
    );
    expect(find.text('igor42'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('is_friend_checkbox')));
    await tester.pumpAndSettle();
    expect(linked, isFalse);
    expect(selected, isNull);
    expect(find.byKey(const ValueKey('friend_selector')), findsNothing);
  });

  group('Recommander à un ami', () {
    testWidgets('envoi désactivé tant qu\'aucun ami n\'est coché', (
      tester,
    ) async {
      RecommendSelection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showModalBottomSheet<RecommendSelection>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const RecommendFriendSheet(
                        itemTitle: 'Azul',
                        friends: _friends,
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
      expect(find.text('Recommander « Azul »'), findsOneWidget);

      final send = find.byKey(const ValueKey('recommend_send'));
      expect(tester.widget<FilledButton>(send).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('recommend_friend_p_igor')));
      await tester.tap(find.byKey(const ValueKey('recommend_friend_p_lou')));
      await tester.pump();
      expect(find.text('Envoyer à 2 amis'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'À tester !');
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(result!.friends.map((f) => f.username), ['igor42', 'loulou']);
      expect(result!.message, 'À tester !');
    });
  });
}
