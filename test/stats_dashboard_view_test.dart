import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/utils/stats_dashboard.dart';
import 'package:collection_app/widgets/cost_per_play_badge.dart';
import 'package:collection_app/widgets/stats/stats_dashboard_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

const _data = StatsDashboard(
  ownedCount: 124,
  expansionCount: 12,
  wishlistCount: 8,
  wishlistValue: 240,
  wishlistPricedCount: 5,
  boardgameCount: 50,
  playedCount: 30,
  unplayedCount: 20,
  totalPlays: 210,
  awayCount: 4,
  loanedCount: 2,
  categories: [
    StatsCategoryBar(category: CollectionCategory.boardgame, count: 50),
    StatsCategoryBar(category: CollectionCategory.book, count: 40),
    StatsCategoryBar(category: CollectionCategory.movie, count: 34),
  ],
  topPlayed: [
    StatsDashboardItem(
      id: '1',
      title: 'Azul',
      category: CollectionCategory.boardgame,
      plays: 40,
    ),
    StatsDashboardItem(
      id: '2',
      title: 'Catan',
      category: CollectionCategory.boardgame,
      plays: 12,
    ),
  ],
);

void main() {
  testWidgets('4 KPI : possédés, wishlist, taux de jeu, hors de chez moi',
      (tester) async {
    await _pump(tester, const StatsDashboardView(data: _data));

    expect(find.text('Objets possédés'), findsOneWidget);
    expect(find.text('124'), findsOneWidget);
    expect(find.text('+ 12 extensions'), findsOneWidget);

    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.textContaining('240 €'), findsOneWidget);

    expect(find.text('Taux de jeu'), findsOneWidget);
    expect(find.text('60 %'), findsOneWidget);
    expect(find.textContaining('Pile de la honte 40 %'), findsOneWidget);
    expect(find.textContaining('210 parties'), findsOneWidget);

    expect(find.text('Hors de chez moi'), findsOneWidget);
    expect(find.text('dont 2 prêtés'), findsOneWidget);
  });

  testWidgets('contenu centré, largeur max 900 sur grand écran',
      (tester) async {
    await _pump(tester, const StatsDashboardView(data: _data));
    final box = tester.getSize(find.byType(ListView));
    expect(box.width, StatsDashboardView.maxContentWidth);
  });

  testWidgets('KPI en 4 colonnes sur PC, 2 colonnes sur mobile',
      (tester) async {
    await _pump(tester, const StatsDashboardView(data: _data));
    final wideY = {
      for (final k in ['kpi_owned', 'kpi_wishlist', 'kpi_play_rate', 'kpi_away'])
        tester.getTopLeft(find.byKey(ValueKey(k))).dy,
    };
    expect(wideY.length, 1);

    await _pump(
      tester,
      const StatsDashboardView(data: _data),
      size: const Size(400, 1400),
    );
    final owned = tester.getTopLeft(find.byKey(const ValueKey('kpi_owned')));
    final wish = tester.getTopLeft(find.byKey(const ValueKey('kpi_wishlist')));
    final rate = tester.getTopLeft(find.byKey(const ValueKey('kpi_play_rate')));
    expect(owned.dy, wish.dy);
    expect(rate.dy, greaterThan(owned.dy));
  });

  testWidgets('barres par catégorie en 2 colonnes sur PC', (tester) async {
    await _pump(tester, const StatsDashboardView(data: _data));
    final a = tester.getTopLeft(find.text('Jeux de société').first);
    final b = tester.getTopLeft(find.text('Livres'));
    expect(a.dy, b.dy);
    expect(find.text('50 · 40 %'), findsOneWidget);
  });

  testWidgets('pas de section vide : top 3 joués sans prix d\'achat',
      (tester) async {
    await _pump(tester, const StatsDashboardView(data: _data));
    expect(find.textContaining('Ajoute des prix'), findsNothing);
    expect(find.text('Valeur de la collection'), findsNothing);
    expect(find.text('Top 5 des plus joués'), findsOneWidget);
    expect(find.text('Azul'), findsOneWidget);
    expect(find.text('40 parties'), findsOneWidget);
  });

  testWidgets('valeur estimée affichée quand des prix existent',
      (tester) async {
    const valued = StatsDashboard(
      ownedCount: 2,
      purchaseValue: 50,
      estimatedValue: 30,
      valuedCount: 2,
      topValued: [
        StatsDashboardItem(
          id: '1',
          title: 'Brass',
          category: CollectionCategory.boardgame,
          value: 50,
        ),
        StatsDashboardItem(
          id: '2',
          title: 'Root',
          category: CollectionCategory.boardgame,
          value: 30,
          isEstimate: true,
        ),
      ],
    );
    await _pump(tester, const StatsDashboardView(data: valued));
    expect(find.text('Valeur de la collection'), findsOneWidget);
    expect(find.text('≈ 80 €'), findsOneWidget);
    expect(find.textContaining('estimés (marché BGG)'), findsOneWidget);
    expect(find.text('estim.'), findsOneWidget);
  });

  testWidgets('tableau vide : KPI à zéro sans crash', (tester) async {
    await _pump(tester, const StatsDashboardView(data: StatsDashboard()));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Aucun jeu de société'), findsOneWidget);
    expect(find.text('Par catégorie'), findsNothing);
  });

  group('CostPerPlayBadge', () {
    testWidgets('affiche « X,XX € / partie »', (tester) async {
      await _pump(
        tester,
        const CostPerPlayBadge(
          purchasePrice: 42,
          estimatedValue: null,
          plays: 12,
        ),
      );
      expect(find.text('3,50 € / partie'), findsOneWidget);
      expect(find.textContaining('Prix d\'achat ÷ 12 parties'), findsOneWidget);
    });

    testWidgets('utilise la valeur estimée sans prix d\'achat', (tester) async {
      await _pump(
        tester,
        const CostPerPlayBadge(
          purchasePrice: null,
          estimatedValue: 10,
          plays: 1,
        ),
      );
      expect(find.text('10,00 € / partie'), findsOneWidget);
      expect(find.textContaining('Valeur estimée ÷ 1 partie'), findsOneWidget);
    });

    testWidgets('masqué sans partie', (tester) async {
      await _pump(
        tester,
        const CostPerPlayBadge(purchasePrice: 42, estimatedValue: null, plays: 0),
      );
      expect(find.textContaining('/ partie'), findsNothing);
    });
  });
}
