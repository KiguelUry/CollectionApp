import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/utils/whereabouts_apply.dart';
import 'package:collection_app/widgets/temporary_loan_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'me-uid';

CollectionItem _item({
  String? locationUserId,
  String? locationLabel,
  Map<String, dynamic>? metadata,
  String? loanedToName,
  DateTime? loanedAt,
}) =>
    CollectionItem(
      id: 'x',
      title: 'Azul',
      category: CollectionCategory.boardgame,
      isWishlist: false,
      locationUserId: locationUserId,
      locationLabel: locationLabel,
      metadata: metadata,
      loanedToName: loanedToName,
      loanedAt: loanedAt,
    );

void main() {
  group('isAwayFromHome', () {
    test('chez moi → non', () {
      expect(
        isAwayFromHome(
          _item(locationUserId: _me, locationLabel: 'Chez moi'),
          meUserId: _me,
        ),
        isFalse,
      );
    });

    test('chez un autre membre → oui', () {
      expect(
        isAwayFromHome(
          _item(locationUserId: 'lou', locationLabel: 'Chez Lou'),
          meUserId: _me,
        ),
        isTrue,
      );
    });

    test('lieu libre → oui, sauf « Chez moi »', () {
      expect(
        isAwayFromHome(_item(metadata: {'holder_label': 'Max'})),
        isTrue,
      );
      expect(
        isAwayFromHome(_item(metadata: {'holder_label': 'Chez moi'})),
        isFalse,
      );
    });

    test('non renseigné → non', () {
      expect(isAwayFromHome(_item(), meUserId: _me), isFalse);
    });
  });

  group('isOnLoan', () {
    test('date seule suffit (saisie du nom en cours)', () {
      expect(
        _item(loanedAt: DateTime(2026, 11, 4)).isOnLoan,
        isTrue,
      );
    });

    test('nom seul suffit', () {
      expect(_item(loanedToName: 'Noé').isOnLoan, isTrue);
    });
  });

  group('applyTemporaryLoan', () {
    test('prêt avec emprunteur explicite (pas le lieu)', () {
      final date = DateTime(2026, 10, 1);
      final loaned = applyTemporaryLoan(
        _item(
          locationUserId: 'lou',
          locationLabel: 'Chez Lou',
          metadata: {'holder_label': 'Braine-l\'Alleud'},
        ),
        isLoan: true,
        loanedAt: date,
        meUserId: _me,
        borrowerName: 'Noé Niche',
      );
      expect(loaned.isOnLoan, isTrue);
      expect(loaned.loanedToName, 'Noé Niche');
      expect(loaned.loanedAt, date);
      // Ne doit PAS recopier le lieu dans « Prêté à ».
      expect(loaned.loanedToName, isNot(contains('Braine')));
    });

    test('sans emprunteur : pas de nom inventé depuis le lieu', () {
      final loaned = applyTemporaryLoan(
        _item(locationLabel: 'Braine-l\'Alleud'),
        isLoan: true,
        meUserId: _me,
      );
      expect(loaned.loanedAt, isNotNull);
      expect(loaned.loanedToName, isNull);
      expect(loaned.isOnLoan, isTrue);
    });

    test('désactivation efface le prêt', () {
      final loaned = applyTemporaryLoan(
        _item(locationUserId: 'lou', locationLabel: 'Chez Lou'),
        isLoan: true,
        meUserId: _me,
        borrowerName: 'Lou',
        borrowerId: 'lou',
      );
      final back = applyTemporaryLoan(loaned, isLoan: false);
      expect(back.isOnLoan, isFalse);
      expect(back.loanedAt, isNull);
      expect(loanDbFields(back), {
        'loaned_to_id': null,
        'loaned_to_name': null,
        'loaned_at': null,
      });
    });

    test('loanDbFields sérialise la date en UTC ISO', () {
      final loaned = applyTemporaryLoan(
        _item(),
        isLoan: true,
        loanedAt: DateTime.utc(2026, 10, 1),
        meUserId: _me,
        borrowerName: 'Lou',
      );
      expect(loanDbFields(loaned)['loaned_at'], '2026-10-01T00:00:00.000Z');
    });

    test('changement de date conserve l\'emprunteur', () {
      final first = applyTemporaryLoan(
        _item(),
        isLoan: true,
        loanedAt: DateTime(2026, 10, 1),
        borrowerName: 'Noé',
      );
      final next = applyTemporaryLoan(
        first,
        isLoan: true,
        loanedAt: DateTime(2026, 10, 15),
      );
      expect(next.loanedToName, 'Noé');
      expect(next.loanedAt, DateTime(2026, 10, 15));
    });
  });

  group('TemporaryLoanToggle', () {
    testWidgets('affiche la date seulement quand le prêt est actif',
        (tester) async {
      bool? lastValue;
      Widget build(bool isLoan) => MaterialApp(
            home: Scaffold(
              body: TemporaryLoanToggle(
                isLoan: isLoan,
                loanedAt: DateTime(2026, 10, 15),
                onChanged: (v, _, {borrowerName}) => lastValue = v,
              ),
            ),
          );

      await tester.pumpWidget(build(false));
      expect(find.text('C\'est un prêt temporaire'), findsOneWidget);
      expect(find.byKey(const ValueKey('temporary_loan_date')), findsNothing);

      // L'activation ouvre un pop-up — on vérifie juste l'état actif.
      expect(lastValue, isNull);

      await tester.pumpWidget(build(true));
      expect(find.text('Prêté le 15/10/2026'), findsOneWidget);
    });
  });
}
