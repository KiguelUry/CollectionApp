import 'collection_category.dart';
import 'book_subcategory.dart';
import 'card_subcategory.dart';
import 'category_metadata.dart';

class CollectionItem {
  final String id;
  final String title;
  final CollectionCategory category;
  final String? subcategory;
  final Map<String, dynamic>? metadata;
  final String? imageUrl;
  final bool isWishlist;
  final String? locationUserId;
  final String? loanedToId;
  final String? loanedToName;
  final int? minPlayers;
  final int? maxPlayers;
  final int? playingTime;
  final String? personalRules;

  CollectionItem({
    required this.id,
    required this.title,
    required this.category,
    this.subcategory,
    this.metadata,
    this.imageUrl,
    required this.isWishlist,
    this.locationUserId,
    this.loanedToId,
    this.loanedToName,
    this.minPlayers,
    this.maxPlayers,
    this.playingTime,
    this.personalRules,
  });

  factory CollectionItem.fromJson(Map<String, dynamic> json) {
    final category = CollectionCategory.fromDbValue(
      json['category'] as String? ?? CollectionCategory.boardgame.dbValue,
    );
    final rawSub = json['subcategory'] as String?;

    return CollectionItem(
      id: json['id'],
      title: json['title'],
      category: category,
      subcategory: category == CollectionCategory.book
          ? (rawSub ?? (json['category'] == 'manga' ? 'manga' : null))
          : rawSub,
      metadata: CategoryMetadata.parse(json['metadata']),
      imageUrl: json['image_url'],
      isWishlist: json['is_wishlist'] ?? false,
      locationUserId: json['location_user_id'],
      loanedToId: json['loaned_to_id'],
      loanedToName: json['loaned_to_name'],
      minPlayers: json['min_players'],
      maxPlayers: json['max_players'],
      playingTime: json['playing_time'],
      personalRules: json['personal_rules'],
    );
  }

  Map<String, dynamic> toInsertJson({
    required bool isWishlist,
    String? locationUserId,
  }) {
    return {
      'title': title,
      'category': category.dbValue,
      'subcategory': subcategory,
      'metadata': metadata ?? {},
      'image_url': imageUrl,
      'is_wishlist': isWishlist,
      'location_user_id': isWishlist ? null : locationUserId,
      'min_players': minPlayers,
      'max_players': maxPlayers,
      'playing_time': playingTime,
    };
  }

  BookSubcategory? get bookSubcategory {
    if (category != CollectionCategory.book) return null;
    return BookSubcategory.fromDbValue(subcategory);
  }

  CardSubcategory? get cardSubcategory {
    if (category != CollectionCategory.card) return null;
    return CardSubcategory.fromDbValue(subcategory);
  }

  String? get listSubtitle => CategoryMetadata.subtitle(this);
}
