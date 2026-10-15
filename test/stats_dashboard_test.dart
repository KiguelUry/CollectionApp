import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/utils/stats_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(
  String id,
  String category, {
  bool wishlist = false,
  bool sold = false,
  bool expansion = false,
  num? price,
  int qty = 1,
  Map<String, dynamic>? meta,
  int? gamesPlayed,
  String? locationUser,
  String? loanedName,
}) =>
    {
      'id': id,
      'title': 'Item $id',
      'category': category,
      'is_wishlist': wishlist,
      'is_sold': sold,
      'is_expansion': expansion,
      'purchase_price': price,
      'quantity': qty,
      'metadata': meta,
      'games_played': gamesPlayed,
      'location_user_id': locationUser,
      'loaned_to_name': loanedName,
    };

Map<String, dynamic> _plays(int n) => {
      'boardgame_plays': [
        for (var i = 0; i < n; i++)
          {
            'date': '2026-01-${(i + 1).toString().padLeft(2, '0')}',
            'players': ['A', 'B'],
          },
      ],
    };

void main() {
  const me = 'me-uid';
  final active = CollectionCategory.defaultActive;

  group('StatsDashboard.fromRows — catégories actives', () {
    test('les catégories désactivées ne gonflent pas le total', () {
      final rows = [
        _row('1', 'boardgame'),
        _row('2', 'book'),
        _row('3', 'animal'),
        _row('4', 'watch'),
        _row('5', 'restaurant'),
      ];
      final d = StatsDashboard.fromRows(rows, active: active, meUserId: me);
      expect(d.ownedCount, 2);
      expect(
        d.categories.map((c) => c.category),
        isNot(contains(CollectionCategory.wildlife)),
      );
    });

    test('wishlist, vendus et extensions séparés', () {
      final rows = [
        _row('1', 'boardgame'),
        _row('2', 'boardgame', wishlist: true, price: 30),
        _row('3', 'boardgame', sold: true),
        _row(
          '4',
          'boardgame',
          expansion: true,
          meta: {'bgg_id': '999'},
        ),
        _row('5', 'boardgame', meta: {
          'owned_expansion_bgg_ids': ['999', '1000'],
        }),
      ];
      final d = StatsDashboard.fromRows(rows, active: active, meUserId: me);
      expect(d.ownedCount, 2);
      expect(d.wishlistCount, 1);
      expect(d.wishlistValue, 30);
      expect(d.expansionCount, 2);
    });

    test('déduplique les lignes par id', () {
      final rows = [_row('1', 'book'), _row('1', 'book')];
      final d = StatsDashboard.fromRows(rows, active: active);
      expect(d.ownedCount, 1);
    });
  });

  group('Taux de jeu', () {
    test('joués vs pile de la honte + total des parties', () {
      final rows = [
        _row('1', 'boardgame', meta: _plays(3)),
        _row('2', 'boardgame', meta: _plays(1)),
        _row('3', 'boardgame'),
        _row('4', 'boardgame', gamesPlayed: 2),
      ];
      final d = StatsDashboard.fromRows(rows, active: active);
      expect(d.boardgameCount, 4);
      expect(d.playedCount, 3);
      expect(d.unplayedCount, 1);
      expect(d.totalPlays, 6);
      expect(d.playedShare, 0.75);
      expect(d.unplayedShare, 0.25);
      expect(d.topPlayed.map((e) => e.id).toList(), ['1', '4', '2']);
    });

    test('aucun jeu → parts nulles', () {
      final d = StatsDashboard.fromRows([_row('1', 'book')], active: active);
      expect(d.playedShare, 0);
      expect(d.unplayedShare, 0);
      expect(d.topPlayed, isEmpty);
    });
  });

  group('Hors de chez moi / prêts', () {
    test('compte autres membres, lieux libres et prêts', () {
      final rows = [
        _row('1', 'book', locationUser: me),
        _row('2', 'book', locationUser: 'other'),
        _row('3', 'book', meta: {'holder_label': 'Lou'}),
        _row('4', 'book', meta: {'holder_label': 'Chez moi'}),
        _row('5', 'book', locationUser: me, loanedName: 'Max'),
        _row('6', 'book'),
      ];
      final d = StatsDashboard.fromRows(rows, active: active, meUserId: me);
      expect(d.awayCount, 3);
      expect(d.loanedCount, 1);
    });
  });

  group('Valorisation', () {
    test('prix d\'achat prioritaire, sinon estimation marché BGG', () {
      final rows = [
        _row('1', 'boardgame', price: 40, qty: 2),
        _row('2', 'boardgame', meta: {'market_secondhand_price': 25}),
        _row('3', 'boardgame', meta: {'market_new_price_min': '18,5'}),
        _row('4', 'boardgame'),
      ];
      final d = StatsDashboard.fromRows(rows, active: active);
      expect(d.purchaseValue, 80);
      expect(d.estimatedValue, closeTo(43.5, 0.001));
      expect(d.valuedCount, 3);
      expect(d.hasValue, isTrue);
      expect(d.topValued.first.id, '1');
      expect(d.topValued.first.isEstimate, isFalse);
      expect(d.topValued[1].isEstimate, isTrue);
    });

    test('aucune valeur → hasValue faux', () {
      final d = StatsDashboard.fromRows([_row('1', 'book')], active: active);
      expect(d.hasValue, isFalse);
      expect(d.topValued, isEmpty);
    });
  });

  group('Coût par partie', () {
    test('prix d\'achat / parties', () {
      expect(costPerPlay(purchasePrice: 42, plays: 12), 3.5);
    });

    test('repli sur valeur estimée', () {
      expect(costPerPlay(estimatedValue: 20, plays: 4), 5);
    });

    test('null sans partie ou sans prix', () {
      expect(costPerPlay(purchasePrice: 42, plays: 0), isNull);
      expect(costPerPlay(plays: 3), isNull);
      expect(costPerPlay(purchasePrice: 0, plays: 3), isNull);
    });

    test('format « X,XX € / partie »', () {
      expect(formatCostPerPlay(3.5), '3,50 € / partie');
    });

    test('formatEuroAmount sépare les milliers', () {
      expect(formatEuroAmount(1234.4), '1\u202f234 €');
      expect(formatEuroAmount(12), '12 €');
    });
  });
}
