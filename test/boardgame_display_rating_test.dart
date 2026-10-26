import 'package:collection_app/utils/boardgame_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('note BGG affichée sur /5 à 1 décimale', () {
    expect(bggRatingOnTen(8.5), 8.5);
    expect(bggRatingOnFive(8.2), 4.1);
    expect(bggRatingOnFive('7.0'), 3.5);
    expect(formatBggRatingChipLabel(8.2), '4.1');
    expect(formatBggRatingStarLabel(8.2), '★ 4.1');
    expect(formatBggRatingStarLabel(null), '…');
  });

  test('note personnelle stockée /5 ; legacy /10 → /5', () {
    expect(personalRatingOnFive(4.0), 4.0);
    expect(personalRatingOnFive(8.2, metadata: {'rating_scale': '10'}), 4.1);
    expect(personalRatingOnFive(9.0), 4.5);
    expect(formatPersonalRatingLabel(3.5), '3.5');
  });

  test('formatPlayerCount n\'affiche jamais 1–1 joueurs', () {
    expect(formatPlayerCount(1, 1), '1 joueur');
    expect(formatPlayerCount(4, 4), '4 joueurs');
    expect(formatPlayerCount(1, 4), '1–4 joueurs');
    expect(formatPlayerCount(2, null), '2 joueurs');
  });
}
