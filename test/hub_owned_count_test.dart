import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/utils/bgg_text.dart';
import 'package:collection_app/utils/hub_owned_count.dart';
import 'package:flutter_test/flutter_test.dart';

CollectionItem _game({
  required String id,
  required String title,
  int quantity = 1,
  bool expansion = false,
  String? parentId,
  Map<String, dynamic>? metadata,
}) {
  return CollectionItem(
    id: id,
    title: title,
    category: CollectionCategory.boardgame,
    isWishlist: false,
    quantity: quantity,
    isExpansion: expansion,
    parentGameId: parentId,
    metadata: metadata,
  );
}

void main() {
  test('grille : une extension liée ne compte pas dans le total', () {
    final items = [
      _game(id: 'a', title: 'Sea Salt & Paper', quantity: 2),
      _game(
        id: 'b',
        title: 'Extension cachée',
        expansion: true,
        parentId: 'a',
        metadata: const {'bgg_is_expansion': true},
      ),
      _game(id: 'c', title: 'Azul'),
    ];
    final visible = visibleOwnedLikeGrid(items);
    expect(visible.map((e) => e.title), ['Sea Salt & Paper', 'Azul']);
    expect(countDuplicateGames(visible), 1);
  });

  test('cleanBggText décode les entités et les sauts de ligne', () {
    expect(
      cleanBggText('Hello&nbsp;world.<br/>Suite &amp; fin'),
      'Hello world.\nSuite & fin',
    );
  });
}