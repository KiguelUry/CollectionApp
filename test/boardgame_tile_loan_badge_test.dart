import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/widgets/boardgame_tile_meta_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CollectionItem _item({String? loanedToName}) => CollectionItem(
      id: 'x',
      title: 'Azul',
      category: CollectionCategory.boardgame,
      isWishlist: false,
      locationUserId: 'lou',
      locationLabel: 'Chez Lou',
      loanedToName: loanedToName,
    );

Future<void> _pump(WidgetTester tester, CollectionItem item) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          child: BoardgameTileMetaIcons(item: item, ownedQuantity: 1),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('badge lieu : icône poignée de main quand prêté', (tester) async {
    await _pump(tester, _item(loanedToName: 'Lou'));
    expect(find.byKey(const ValueKey('loan_location_chip')), findsOneWidget);
    expect(find.byIcon(Icons.handshake_outlined), findsOneWidget);
    expect(find.text('Lou'), findsOneWidget);
  });

  testWidgets('badge lieu classique sans prêt', (tester) async {
    await _pump(tester, _item());
    expect(find.byKey(const ValueKey('loan_location_chip')), findsNothing);
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
  });
}
