import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/models/item_condition.dart';
import 'package:collection_app/utils/holder_filter.dart';
import 'package:collection_app/utils/item_copy_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readCopyUnits seeds first copy from item fields', () {
    final item = CollectionItem(
      id: 'a',
      title: 'Test',
      category: CollectionCategory.boardgame,
      isWishlist: false,
      quantity: 2,
      locationUserId: 'me',
      locationLabel: 'Chez moi',
      purchasePrice: 30,
      condition: ItemCondition.bon.dbValue,
    );
    final units = readCopyUnits(item);
    expect(units.length, 2);
    expect(units.first.locationUserId, 'me');
    expect(units.first.purchasePrice, 30);
    expect(units.first.condition, ItemCondition.bon);
  });

  test('holder filter matches any copy location', () {
    final item = CollectionItem(
      id: 'b',
      title: 'Sea Salt',
      category: CollectionCategory.boardgame,
      isWishlist: false,
      quantity: 2,
      metadata: {
        kCopyUnitsMetadataKey: [
          {
            'index': 0,
            'location_user_id': 'me',
            'location_label': 'Chez moi',
          },
          {
            'index': 1,
            'holder_label': 'papa',
            'location_label': 'Chez Papa',
          },
        ],
      },
    );
    expect(itemMatchesHolderKey(item, 'user:me'), isTrue);
    expect(itemMatchesHolderKey(item, 'custom:papa'), isTrue);
    expect(itemMatchesHolderKey(item, 'custom:maman'), isFalse);
  });

  test('quickWhereabouts prefers chez moi among copies', () {
    final item = CollectionItem(
      id: 'c',
      title: 'X',
      category: CollectionCategory.boardgame,
      isWishlist: false,
      quantity: 2,
      metadata: {
        kCopyUnitsMetadataKey: [
          {'index': 0, 'holder_label': 'papa', 'location_label': 'Chez Papa'},
          {'index': 1, 'location_user_id': 'me', 'location_label': 'Chez moi'},
        ],
      },
    );
    expect(
      quickWhereaboutsSummaryLabel(item, meUserId: 'me'),
      'Chez moi',
    );
  });
}
