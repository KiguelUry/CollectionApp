import 'package:collection_app/services/player_alias_service.dart';
import 'package:collection_app/widgets/player_alias_linker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('aliasCollisionKey', () {
    test('ignore casse et espaces', () {
      expect(aliasCollisionKey('Lou'), aliasCollisionKey('lou'));
      expect(aliasCollisionKey(' Jean Paul '), aliasCollisionKey('jeanpaul'));
      expect(aliasCollisionKey('Lou'), isNot(aliasCollisionKey('Louise')));
    });
  });

  group('findAliasCollisions', () {
    test('regroupe les variantes de casse / espaces', () {
      final groups = findAliasCollisions(
        ['Lou', 'lou', 'Louise', 'Jean Paul', 'JeanPaul', 'Max'],
      );
      expect(groups, [
        ['Lou', 'lou'],
        ['Jean Paul', 'JeanPaul'],
      ]);
    });

    test('aucun doublon → liste vide', () {
      expect(findAliasCollisions(['A', 'B', 'C']), isEmpty);
    });

    test('ignore doublons exacts et noms vides', () {
      expect(findAliasCollisions(['Lou', 'Lou', '', '  ']), isEmpty);
    });

    test('ignore les groupes déjà liés à la même identité', () {
      final groups = findAliasCollisions(
        ['Lou', 'lou', 'Max', 'MAX'],
        identityIdOf: (n) => n.toLowerCase() == 'lou' ? 'id-lou' : null,
      );
      expect(groups, [
        ['Max', 'MAX'],
      ]);
    });

    test('identités différentes → toujours signalé', () {
      final groups = findAliasCollisions(
        ['Lou', 'lou'],
        identityIdOf: (n) => n == 'Lou' ? 'a' : 'b',
      );
      expect(groups.length, 1);
    });
  });

  testWidgets('AliasCollisionWarning affiche les pseudos et propose la fusion',
      (tester) async {
    var merged = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AliasCollisionWarning(
            names: const ['Lou', 'lou'],
            onMerge: () => merged++,
          ),
        ),
      ),
    );
    expect(find.textContaining('« Lou »'), findsOneWidget);
    expect(find.textContaining('« lou »'), findsOneWidget);
    await tester.tap(find.text('Fusionner'));
    expect(merged, 1);
  });

  testWidgets('AliasCollisionWarning désactivé pendant une sauvegarde',
      (tester) async {
    var merged = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AliasCollisionWarning(
            names: const ['Lou', 'lou'],
            enabled: false,
            onMerge: () => merged++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fusionner'));
    expect(merged, 0);
  });
}
