import 'package:collection_app/constants/rating_colors.dart';
import 'package:collection_app/utils/tile_rating_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveTileRating', () {
    test('personal_then_community préfère le perso bleu', () {
      final chip = resolveTileRating(
        personalOnFive: 4.2,
        communityOnFive: 3.8,
        mode: TileRatingDisplayMode.personalThenCommunity,
      );
      expect(chip.label, '★ 4.2');
      expect(chip.color, RatingColors.personal);
      expect(chip.isPersonal, isTrue);
    });

    test('personal_then_community tombe sur communauté or', () {
      final chip = resolveTileRating(
        personalOnFive: null,
        communityOnFive: 4.4,
        mode: TileRatingDisplayMode.personalThenCommunity,
      );
      expect(chip.label, '★ 4.4');
      expect(chip.color, RatingColors.community);
      expect(chip.isPersonal, isFalse);
    });

    test('always_community ignore le perso', () {
      final chip = resolveTileRating(
        personalOnFive: 5.0,
        communityOnFive: 3.1,
        mode: TileRatingDisplayMode.alwaysCommunity,
      );
      expect(chip.label, '★ 3.1');
      expect(chip.isPersonal, isFalse);
    });

    test('only_personal sans note → tiret', () {
      final chip = resolveTileRating(
        personalOnFive: null,
        communityOnFive: 4.0,
        mode: TileRatingDisplayMode.onlyPersonal,
      );
      expect(chip.label, '★ —');
    });
  });
}
