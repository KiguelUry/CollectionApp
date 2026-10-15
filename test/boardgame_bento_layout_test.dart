import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/widgets/boardgame/boardgame_item_bento_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('grille Bento sans overflow sur mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final item = CollectionItem(
      id: 'x',
      title: 'Catan',
      category: CollectionCategory.boardgame,
      isWishlist: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BoardgameDetailWidthLimiter(
              child: Column(
                children: [
                  BoardgameDetailCompactHeader(item: item),
                  const SizedBox(height: 12),
                  BoardgameBentoGrid(
                    children: [
                      BoardgameBentoSummaryTile(
                        icon: Icons.inventory_2_outlined,
                        title: 'Ma boîte',
                        subtitle: 'Quantité ×1',
                        accent: Colors.orange,
                        onOpenDetail: () {},
                      ),
                      BoardgameBentoSummaryTile(
                        icon: Icons.info_outline,
                        title: 'Infos BGG',
                        subtitle: 'Description',
                        accent: Colors.blue,
                        onOpenDetail: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Catan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
