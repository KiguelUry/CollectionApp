import '../models/collection_item.dart';
import '../services/inventory_service.dart';
import '../utils/collection_item_scope.dart';

enum FriendOverlapKind { none, inCollection, inWishlist }

String _norm(String s) => s.trim().toLowerCase();

/// Clés d'identité catalogue d'un objet : `bgg:<id>` en priorité (stable même
/// si le jeu est renommé), puis titre affiché et titre d'origine.
Set<String> overlapKeysFor({
  required String categoryDb,
  required String title,
  String? bggId,
  String? originalTitle,
}) {
  final keys = <String>{};
  final bgg = bggId?.trim();
  if (bgg != null && bgg.isNotEmpty && bgg != 'null') {
    keys.add('bgg:$bgg');
  }
  if (title.trim().isNotEmpty) keys.add('$categoryDb|${_norm(title)}');
  final orig = originalTitle?.trim();
  if (orig != null && orig.isNotEmpty) keys.add('$categoryDb|${_norm(orig)}');
  return keys;
}

Set<String> overlapKeysForItem(CollectionItem item) => overlapKeysFor(
      categoryDb: item.category.dbValue,
      title: item.title,
      bggId: item.metadata?['bgg_id']?.toString(),
      originalTitle: item.metadata?['original_title']?.toString(),
    );

/// Lignes légères `{title, category, bgg_id, original_title}`.
Set<String> overlapKeysForRow(Map<String, dynamic> row) => overlapKeysFor(
      categoryDb: row['category']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      bggId: row['bgg_id']?.toString(),
      originalTitle: row['original_title']?.toString(),
    );

Set<String> overlapKeysForRows(Iterable<Map<String, dynamic>> rows) => {
      for (final r in rows) ...overlapKeysForRow(r),
    };

/// Retire les doublons accidentels (même `bgg_id` ou même titre) — ex.
/// « Toy Battle » ajouté 3 fois en wishlist par un double-tap.
List<CollectionItem> dedupeCatalogItems(List<CollectionItem> items) {
  final seen = <String>{};
  final out = <CollectionItem>[];
  for (final item in items) {
    final keys = overlapKeysForItem(item);
    if (keys.any(seen.contains)) continue;
    seen.addAll(keys);
    out.add(item);
  }
  return out;
}

class FriendOverlapIndex {
  final Set<String> _ownedKeys;
  final Set<String> _wishKeys;

  FriendOverlapIndex(this._ownedKeys, this._wishKeys);

  static final empty = FriendOverlapIndex(const {}, const {});

  FriendOverlapKind kindFor(CollectionItem friendItem) {
    final keys = overlapKeysForItem(friendItem);
    if (keys.any(_ownedKeys.contains)) return FriendOverlapKind.inCollection;
    if (keys.any(_wishKeys.contains)) return FriendOverlapKind.inWishlist;
    return FriendOverlapKind.none;
  }

  bool isCommon(CollectionItem friendItem) =>
      kindFor(friendItem) == FriendOverlapKind.inCollection;

  /// Nombre d'objets distincts de l'ami (par identité catalogue) que tu as.
  int countIn(List<CollectionItem> friendItems, FriendOverlapKind kind) {
    var n = 0;
    for (final item in dedupeCatalogItems(friendItems)) {
      if (kindFor(item) == kind) n++;
    }
    return n;
  }

  /// Construit l'index à partir de mes lignes légères.
  factory FriendOverlapIndex.fromMyRows(Iterable<Map<String, dynamic>> rows) {
    final owned = <String>{};
    final wish = <String>{};
    for (final r in rows) {
      final keys = overlapKeysForRow(r);
      if (r['is_wishlist'] == true) {
        wish.addAll(keys);
      } else {
        owned.addAll(keys);
      }
    }
    return FriendOverlapIndex(owned, wish);
  }
}

/// Ligne légère d'un de mes objets (pour [FriendOverlapIndex.fromMyRows]).
Map<String, dynamic> overlapRowOf(CollectionItem item) => {
      'title': item.title,
      'category': item.category.dbValue,
      'is_wishlist': item.isWishlist,
      'bgg_id': item.metadata?['bgg_id']?.toString(),
      'original_title': item.metadata?['original_title']?.toString(),
    };

/// Mes objets (ajoutés par moi ou chez moi), depuis le cache inventaire :
/// aucune requête en plus si le hub est déjà chargé.
Future<List<CollectionItem>> myOverlapItems() async {
  final userId = CollectionItemScope.currentUserId;
  if (userId == null) return const [];
  final items = await InventoryService().fetchOwnedItems();
  return [
    for (final i in items)
      if (i.addedBy == userId || i.locationUserId == userId) i,
  ];
}

/// Index de ce que tu possèdes / souhaites, pour comparer avec un ami.
Future<FriendOverlapIndex> buildFriendOverlapIndex(
  List<CollectionItem> friendItems,
) async {
  if (friendItems.isEmpty) return FriendOverlapIndex.empty;
  final mine = await myOverlapItems();
  return FriendOverlapIndex.fromMyRows(mine.map(overlapRowOf));
}
