import 'package:collection_app/models/collection_list_filters.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/widgets/item_customize_sheet.dart';
import 'package:collection_app/widgets/social_activity_post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mosaic density', () {
    test('auto scale', () {
      expect(resolveMosaicTiles(1, FeedMosaicDensity.auto), 1);
      expect(resolveMosaicTiles(2, FeedMosaicDensity.auto), 2);
      expect(resolveMosaicTiles(4, FeedMosaicDensity.auto), 4);
      expect(resolveMosaicTiles(6, FeedMosaicDensity.auto), 6);
      expect(resolveMosaicTiles(8, FeedMosaicDensity.auto), 9);
      expect(resolveMosaicTiles(9, FeedMosaicDensity.auto), 9);
      expect(resolveMosaicTiles(40, FeedMosaicDensity.auto), 12);
    });

    test('fixed density', () {
      expect(resolveMosaicTiles(50, FeedMosaicDensity.four), 4);
      // Densité forcée plafonnée au nb d'événements (pas de cases vides).
      expect(resolveMosaicTiles(1, FeedMosaicDensity.sixteen), 1);
      expect(resolveMosaicTiles(20, FeedMosaicDensity.sixteen), 16);
    });
  });

  group('boardgame filters', () {
    CollectionItem game({
      int? min,
      int? max,
      int? time,
      int plays = 0,
      double? weight,
      bool forSale = false,
    }) {
      return CollectionItem(
        id: 'x',
        title: 'Test',
        category: CollectionCategory.boardgame,
        isWishlist: false,
        minPlayers: min,
        maxPlayers: max,
        playingTime: time,
        gamesPlayed: plays,
        isForSale: forSale,
        metadata: {
          if (weight != null) 'bgg_weight': weight,
          'bgg_best_players': [2],
        },
      );
    }

    test('player count + best only', () {
      final g = game(min: 2, max: 4);
      expect(
        CollectionListFilters.matchesPlayerCount(g, 3, bestOnly: false),
        isTrue,
      );
      expect(
        CollectionListFilters.matchesPlayerCount(g, 2, bestOnly: true),
        isTrue,
      );
      expect(
        CollectionListFilters.matchesPlayerCount(g, 4, bestOnly: true),
        isFalse,
      );
    });

    test('duration buckets', () {
      final g = game(time: 45);
      expect(
        CollectionListFilters.matchesDuration(
          g,
          {BoardgameDurationBucket.from30to60},
        ),
        isTrue,
      );
      expect(
        CollectionListFilters.matchesDuration(
          g,
          {BoardgameDurationBucket.under30},
        ),
        isFalse,
      );
    });

    test('complexity bands', () {
      final g = game(weight: 3.5);
      expect(
        CollectionListFilters.matchesComplexity(
          g,
          {BoardgameComplexityBand.expert},
        ),
        isTrue,
      );
    });

    test('apply filters combine', () {
      final items = [
        game(min: 2, max: 2, time: 20, plays: 0, weight: 1.5),
        game(min: 3, max: 5, time: 90, plays: 4, weight: 3.4, forSale: true),
      ];
      final f = CollectionListFilters(
        playerCounts: {2},
        durationBuckets: {BoardgameDurationBucket.under30},
        playStatus: BoardgamePlayStatusFilter.neverPlayed,
      );
      final out = f.apply(items);
      expect(out, hasLength(1));
      expect(out.first.playingTime, 20);
    });
  });

  group('avatars storage path', () {
    test('extracts covers path', () {
      final url =
          'https://x.supabase.co/storage/v1/object/public/avatars/uid/covers/item-1.jpg';
      expect(avatarsStoragePathFromUrl(url), 'uid/covers/item-1.jpg');
      expect(avatarsStoragePathFromUrl('https://cdn.example/cover.jpg'), isNull);
    });
  });
}
