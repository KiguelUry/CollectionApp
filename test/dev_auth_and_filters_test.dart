import 'package:collection_app/config/dev_auth_config.dart';
import 'package:collection_app/models/collection_list_filters.dart';
import 'package:collection_app/models/boardgame_score_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DevAuthConfig', () {
    test('accès dotenv sans init ne plante pas', () {
      // En test, dotenv n'est souvent pas chargé : ne doit pas throw.
      expect(() => DevAuthConfig.testEmail, returnsNormally);
      expect(() => DevAuthConfig.testPassword, returnsNormally);
      expect(() => DevAuthConfig.loginButtonLabel, returnsNormally);
      expect(DevAuthConfig.loginButtonLabel, isNotEmpty);
    });
  });

  group('CollectionListFilters', () {
    test('tri par défaut = titre A→Z (Tri inactif)', () {
      final f = CollectionListFilters();
      expect(f.sort, CollectionSort.titleAsc);
      expect(f.hasActiveFilterCriteria, isFalse);
    });

    test('wishlist défaut favoris : Tri inactif si defaultSort=favoritesFirst', () {
      final f = CollectionListFilters(sort: CollectionSort.favoritesFirst);
      // Même logique que CollectionFilterBar.defaultSort wishlist.
      expect(f.sort != CollectionSort.favoritesFirst, isFalse);
      expect(f.sort != CollectionSort.titleAsc, isTrue);
    });

    test('changer le tri active hasActiveFilters (pas le badge Filtre)', () {
      final f = CollectionListFilters(sort: CollectionSort.ratingDesc);
      expect(f.hasActiveFilters, isTrue);
      expect(f.hasActiveFilterCriteria, isFalse);
    });

    test('wishlistMineOnly seul ne compte pas comme filtre utilisateur', () {
      final f = CollectionListFilters(
        wishlistMineOnly: true,
        wishlistMineUserId: 'u1',
      );
      // hasActiveFilterCriteria exclut wishlistMineOnly (scope par défaut).
      expect(f.hasActiveFilterCriteria, isFalse);
    });
  });

  group('ScoreRule phrases', () {
    test('phrases lisibles pour conditions OR typiques', () {
      expect(
        const ScoreRule(
          target: ScoreRuleTarget.total,
          op: ScoreRuleOp.gte,
          value: 5,
        ).phrase,
        'Score total ≥ 5',
      );
      expect(
        const ScoreRule(
          target: ScoreRuleTarget.anyLine,
          op: ScoreRuleOp.gte,
          value: 3,
        ).phrase,
        'Au moins 1 catégorie ≥ 3',
      );
      expect(
        const ScoreRule(
          target: ScoreRuleTarget.filledLineCount,
          op: ScoreRuleOp.gte,
          value: 4,
          cellValue: 1,
        ).phrase,
        'Au moins 4 catégories ≥ 1',
      );
    });
  });
}
