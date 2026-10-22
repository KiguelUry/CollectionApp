import 'package:collection_app/utils/boardgame_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('note BGG /10 convertie en /5 à 1 décimale', () {
    expect(bggRatingOnFive(8.5), 4.3);
    expect(bggRatingOnFive('7.0'), 3.5);
    expect(formatBggRatingChipLabel(8.5), '4.3');
    expect(formatBggRatingStarLabel(8.5), '★ 4.3');
    expect(formatBggRatingStarLabel(null), '…');
  });
}
