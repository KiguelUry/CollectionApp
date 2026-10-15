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
}) =>
    CollectionItem(
      id: 'x',
      title: 'Azul',
      category: CollectionCategory.boardgame,
      isWishlist: false,
      locationUserId: locationUserId,
      locationLabel: locationLabel,
      metadata: metadata,
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

  group('applyTemporaryLoan', () {
    test('prêt à un membre : id + nom sans préfixe + date', () {
      final date = DateTime(2026, 10, 1);
      final loaned = applyTemporaryLoan(
        _item(locationUserId: 'lou', locationLabel: 'Chez Lou'),
        isLoan: true,
        loanedAt: date,
        meUserId: _me,
      );
      expect(loaned.isOnLoan, isTrue);
      expect(loaned.loanedToId, 'lou');
      expect(loaned.loanedToName, 'Lou');
      expect(loaned.loanedAt, date);
    });

    test('prêt hors app (lieu libre) : pas d\'id', () {
      final loaned = applyTemporaryLoan(
        _item(locationLabel: 'Chez Max', metadata: {'holder_label': 'Max'}),
        isLoan: true,
        meUserId: _me,
      );
      expect(loaned.loanedToId, isNull);
      expect(loaned.loanedToName, 'Max');
      expect(loaned.loanedAt, isNotNull);
    });

    test('désactivation efface le prêt', () {
      final loaned = applyTemporaryLoan(
        _item(locationUserId: 'lou', locationLabel: 'Chez Lou'),
        isLoan: true,
        meUserId: _me,
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
        _item(locationUserId: 'lou', locationLabel: 'Chez Lou'),
        isLoan: true,
        loanedAt: DateTime.utc(2026, 10, 1),
        meUserId: _me,
      );
      expect(loanDbFields(loaned)['loaned_at'], '2026-10-01T00:00:00.000Z');
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
                onChanged: (v, _) => lastValue = v,
              ),
            ),
          );

      await tester.pumpWidget(build(false));
      expect(find.text('C\'est un prêt temporaire'), findsOneWidget);
      expect(find.byKey(const ValueKey('temporary_loan_date')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('temporary_loan_switch')));
      expect(lastValue, isTrue);

      await tester.pumpWidget(build(true));
      expect(find.text('Prêté le 15/10/2026'), findsOneWidget);
    });
  });
}
