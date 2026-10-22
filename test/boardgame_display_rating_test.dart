import 'package:collection_app/utils/boardgame_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('note BGG affichée sur /10 à 1 décimale', () {
    expect(bggRatingOnTen(8.5), 8.5);
    expect(bggRatingOnTen('7.0'), 7.0);
    expect(formatBggRatingChipLabel(8.5), '8.5');
    expect(formatBggRatingStarLabel(8.5), '★ 8.5');
    expect(formatBggRatingStarLabel(null), '…');
  });

  test('note personnelle legacy /5 → /10', () {
    expect(personalRatingOnTen(4.0), 8.0);
    expect(personalRatingOnTen(4.15, metadata: {'rating_scale': '10'}), 4.2);
    expect(formatPersonalRatingLabel(3.5), '7.0');
  });
}
