import 'collection_item.dart';

class BookAuthorGroup {
  final String author;
  final List<CollectionItem> items;
  final String? photoUrl;

  const BookAuthorGroup({
    required this.author,
    required this.items,
    this.photoUrl,
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
        (e) {
          String? photo;
          for (final item in e.value) {
            final url = item.metadata?['author_photo_url']?.toString();
            if (url != null && url.isNotEmpty) {
              photo = url;
              break;
            }
          }
          return BookAuthorGroup(
            author: e.key,
            items: e.value,
            photoUrl: photo,
          );
        },
      )
      .toList();
  groups.sort((a, b) => a.author.compareTo(b.author));
  return groups;
}
