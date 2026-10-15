import 'dart:math';

import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/utils/hub_greeting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Random contrôlé : nextDouble renvoie [roll], nextInt renvoie [intValue].
class _FixedRandom implements Random {
  final double roll;
  final int intValue;
  _FixedRandom(this.roll, [this.intValue = 0]);

  @override
  double nextDouble() => roll;

  @override
  int nextInt(int max) => intValue.clamp(0, max - 1);

  @override
  bool nextBool() => false;
}

void main() {
  group('Listes de titres', () {
    test('15 titres généraux', () {
      expect(kGeneralGreetingTitles.length, 15);
      expect(kGeneralGreetingTitles.first, 'Aventurier');
      expect(kGeneralGreetingTitles.last, 'Légende du Butin');
    });

    test('15 surnoms pour chacune des 7 catégories actives', () {
      expect(
        kCategoryGreetingTitles.keys.toSet(),
        CollectionCategory.defaultActive,
      );
      for (final list in kCategoryGreetingTitles.values) {
        expect(list.length, 15);
        expect(list.toSet().length, 15);
      }
      expect(
        kCategoryGreetingTitles[CollectionCategory.boardgame]!.first,
        'Maître du Jeu',
      );
      expect(
        kCategoryGreetingTitles[CollectionCategory.movie]!.last,
        'Critique de l\'Ombre',
      );
    });
  });

  group('pickHubGreeting', () {
    final counts = {
      CollectionCategory.boardgame: 90,
      CollectionCategory.book: 10,
    };

    test('roll < 0.2 → pseudo', () {
      final g = pickHubGreeting(
        username: 'Kiki',
        counts: counts,
        random: _FixedRandom(0.1),
      );
      expect(g.source, HubGreetingSource.pseudo);
      expect(g.text, 'Salut Kiki');
    });

    test('0.2 ≤ roll < 0.4 → titre général', () {
      final g = pickHubGreeting(
        username: 'Kiki',
        counts: counts,
        random: _FixedRandom(0.3, 1),
      );
      expect(g.source, HubGreetingSource.general);
      expect(g.name, kGeneralGreetingTitles[1]);
    });

    test('roll ≥ 0.4 → surnom de catégorie pondéré', () {
      final g = pickHubGreeting(
        username: 'Kiki',
        counts: counts,
        random: _FixedRandom(0.9, 95),
      );
      expect(g.source, HubGreetingSource.category);
      expect(g.category, CollectionCategory.book);
      expect(
        kCategoryGreetingTitles[CollectionCategory.book],
        contains(g.name),
      );
    });

    test('sans objet → repli sur titre général', () {
      final g = pickHubGreeting(
        username: 'Kiki',
        counts: const {},
        random: _FixedRandom(0.9),
      );
      expect(g.source, HubGreetingSource.general);
    });

    test('catégories inactives ignorées', () {
      final g = pickHubGreeting(
        username: 'Kiki',
        counts: {
          CollectionCategory.watch: 500,
          CollectionCategory.lego: 1,
        },
        active: CollectionCategory.defaultActive,
        random: _FixedRandom(0.9, 0),
      );
      expect(g.category, CollectionCategory.lego);
    });

    test('distribution ≈ 20 / 20 / 60 et pondération par volume', () {
      final rng = Random(42);
      final bySource = <HubGreetingSource, int>{};
      final byCat = <CollectionCategory, int>{};
      const n = 20000;
      for (var i = 0; i < n; i++) {
        final g = pickHubGreeting(
          username: 'Kiki',
          counts: counts,
          random: rng,
        );
        bySource[g.source] = (bySource[g.source] ?? 0) + 1;
        if (g.category != null) {
          byCat[g.category!] = (byCat[g.category!] ?? 0) + 1;
        }
      }
      expect(bySource[HubGreetingSource.pseudo]! / n, closeTo(0.2, 0.02));
      expect(bySource[HubGreetingSource.general]! / n, closeTo(0.2, 0.02));
      expect(bySource[HubGreetingSource.category]! / n, closeTo(0.6, 0.02));
      final catTotal = byCat.values.fold<int>(0, (a, b) => a + b);
      expect(
        byCat[CollectionCategory.boardgame]! / catTotal,
        closeTo(0.9, 0.02),
      );
    });
  });
}
