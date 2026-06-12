import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/collection_item_scope.dart';

enum FriendOverlapKind { none, inCollection, inWishlist }

class FriendOverlapIndex {
  final Map<String, FriendOverlapKind> _byKey;

  FriendOverlapIndex._(this._byKey);

  static String keyFor(CollectionItem item) =>
      '${item.category.dbValue}|${item.title.trim().toLowerCase()}';

  FriendOverlapKind kindFor(CollectionItem friendItem) =>
      _byKey[keyFor(friendItem)] ?? FriendOverlapKind.none;

  int get inCollectionCount =>
      _byKey.values.where((k) => k == FriendOverlapKind.inCollection).length;

  int get inWishlistCount =>
      _byKey.values.where((k) => k == FriendOverlapKind.inWishlist).length;
}

/// Index des titres que tu possèdes déjà vs ceux d'un ami.
Future<FriendOverlapIndex> buildFriendOverlapIndex(
  List<CollectionItem> friendItems,
) async {
  if (friendItems.isEmpty) return FriendOverlapIndex._({});

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return FriendOverlapIndex._({});

  final categories = friendItems.map((i) => i.category.dbValue).toSet();

  final rows = await CollectionItemScope.personal(
    client
        .from('collection_items')
        .select('title, category, is_wishlist')
        .inFilter('category', categories.toList()),
    userId: userId,
  );

  final mine = <String, FriendOverlapKind>{};
  for (final row in rows as List) {
    final title = (row['title'] as String?)?.trim().toLowerCase();
    if (title == null || title.isEmpty) continue;
    final cat = row['category'] as String;
    final k = '$cat|$title';
    final wish = row['is_wishlist'] as bool? ?? false;
    if (wish) {
      mine.putIfAbsent(k, () => FriendOverlapKind.inWishlist);
    } else {
      mine[k] = FriendOverlapKind.inCollection;
    }
  }

  final overlap = <String, FriendOverlapKind>{};
  for (final item in friendItems) {
    final k = FriendOverlapIndex.keyFor(item);
    final kind = mine[k];
    if (kind != null) overlap[k] = kind;
  }

  return FriendOverlapIndex._(overlap);
}
