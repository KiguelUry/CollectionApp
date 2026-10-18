import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/utils/collection_pick_dedupe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('déduplique par id, bgg_id et titre', () {
    final items = [
      CollectionItem(
        id: 'a',
        title: 'The Vale of Eternity',
        category: CollectionCategory.boardgame,
        isWishlist: false,
        metadata: {'bgg_id': '100'},
        imageUrl: 'https://img/a.jpg',
      ),
      CollectionItem(
        id: 'b',
        title: 'The Vale of Eternity',
        category: CollectionCategory.boardgame,
        isWishlist: false,
        metadata: {'bgg_id': '100'},
        imageUrl: 'https://img/b.jpg',
      ),
      CollectionItem(
        id: 'c',
        title: 'Zenith',
        category: CollectionCategory.boardgame,
        isWishlist: false,
      ),
    ];
    final out = dedupeCollectionItemsForPick(items);
    expect(out, hasLength(2));
    expect(out.map((i) => i.id), ['a', 'c']);
  });
}
