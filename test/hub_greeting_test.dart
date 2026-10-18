import 'dart:math';

import 'package:collection_app/utils/hub_greeting.dart';
import 'package:flutter_test/flutter_test.dart';

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
  test('titres uniques, Aventurier en tête', () {
    expect(kGreetingTitles.first, 'Aventurier');
    expect(kGreetingTitles.toSet().length, kGreetingTitles.length);
  });

  test('roll < 0.2 → pseudo', () {
    final g = pickHubGreeting(username: 'Kiki', random: _FixedRandom(0.1));
    expect(g.source, HubGreetingSource.pseudo);
    expect(g.text, 'Salut Kiki');
  });

  test('roll ≥ 0.2 → titre', () {
    final g = pickHubGreeting(username: 'Kiki', random: _FixedRandom(0.5, 2));
    expect(g.source, HubGreetingSource.title);
    expect(g.name, kGreetingTitles[2]);
  });

  test('pas deux fois le même titre de suite', () {
    final g = pickHubGreeting(
      username: 'Kiki',
      previous: kGreetingTitles[3],
      random: _FixedRandom(0.5, 3),
    );
    expect(g.name, isNot(kGreetingTitles[3]));
  });

  test('distribution ≈ 20 / 80', () {
    final rng = Random(42);
    var pseudo = 0;
    const n = 20000;
    for (var i = 0; i < n; i++) {
      if (pickHubGreeting(username: 'Kiki', random: rng).source ==
          HubGreetingSource.pseudo) {
        pseudo++;
      }
    }
    expect(pseudo / n, closeTo(0.2, 0.02));
  });
}
