import 'collection_item.dart';

class BookAuthorGroup {
  final String author;
  final List<CollectionItem> items;

  const BookAuthorGroup({
    required this.author,
    required this.items,
  });

  int get ownedCount =>
      items.where((i) => !i.isWishlist && !i.isSold).length;

  int get wishlistCount => items.where((i) => i.isWishlist).length;

  int get totalCount => items.length;
}

List<BookAuthorGroup> groupBooksByAuthor(List<CollectionItem> items) {
  final map = <String, List<CollectionItem>>{};
  for (final item in items) {
    final author = (item.metadata?['author'] as String?)?.trim();
    if (author == null || author.isEmpty) continue;
    map.putIfAbsent(author, () => []).add(item);
  }
  final groups = map.entries
      .map(
        (e) => BookAuthorGroup(
          author: e.key,
          items: e.value,
        ),
      )
      .toList();
  groups.sort((a, b) => a.author.compareTo(b.author));
  return groups;
}
