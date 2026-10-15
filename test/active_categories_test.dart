import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/utils/active_categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CollectionCategory.defaultActive', () {
    test('contient exactement les 7 catégories actives', () {
      expect(CollectionCategory.defaultActive, {
        CollectionCategory.boardgame,
        CollectionCategory.book,
        CollectionCategory.card,
        CollectionCategory.media,
        CollectionCategory.lego,
        CollectionCategory.videogame,
        CollectionCategory.movie,
      });
    });

    test('exclut lab et catégories retirées', () {
      for (final c in [
        CollectionCategory.wildlife,
        CollectionCategory.watch,
        CollectionCategory.tech,
        CollectionCategory.restaurant,
        CollectionCategory.car,
        CollectionCategory.custom,
      ]) {
        expect(CollectionCategory.defaultActive.contains(c), isFalse);
      }
    });
  });

  group('ActiveCategories.resolve', () {
    test('masquage lab par défaut = 7 catégories', () {
      final hidden = CollectionCategory.labCategories.map((c) => c.dbValue);
      expect(
        ActiveCategories.resolve(hiddenDbValues: hidden.toSet()),
        CollectionCategory.defaultActive,
      );
    });

    test('une catégorie masquée par l\'utilisateur disparaît', () {
      final hidden = {
        ...CollectionCategory.labCategories.map((c) => c.dbValue),
        CollectionCategory.card.dbValue,
      };
      final active = ActiveCategories.resolve(hiddenDbValues: hidden);
      expect(active.contains(CollectionCategory.card), isFalse);
      expect(active.length, 6);
    });

    test('les catégories retirées du menu ne reviennent jamais', () {
      final active = ActiveCategories.resolve(hiddenDbValues: {});
      expect(active.contains(CollectionCategory.car), isFalse);
      expect(active.contains(CollectionCategory.custom), isFalse);
      expect(active.contains(CollectionCategory.wildlife), isTrue);
    });
  });

  group('ActiveCategories.filterRows', () {
    final active = CollectionCategory.defaultActive;

    test('garde seulement les lignes de catégories actives', () {
      final rows = [
        {'id': '1', 'category': 'boardgame'},
        {'id': '2', 'category': 'animal'},
        {'id': '3', 'category': 'watch'},
        {'id': '4', 'category': 'book'},
        {'id': '5', 'category': 'manga'},
      ];
      final ids = ActiveCategories.filterRows(rows, active)
          .map((r) => r['id'])
          .toList();
      expect(ids, ['1', '4', '5']);
    });

    test('ignore les valeurs inconnues ou vides (pas de repli boardgame)', () {
      final rows = [
        {'id': '1', 'category': 'inconnue'},
        {'id': '2', 'category': ''},
        {'id': '3', 'category': null},
      ];
      expect(ActiveCategories.filterRows(rows, active), isEmpty);
    });
  });
}
