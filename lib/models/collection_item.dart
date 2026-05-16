import 'collection_category.dart';

class CollectionItem {
  final String id;
  final String title;
  final CollectionCategory category;
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
    return CollectionItem(
      id: json['id'],
      title: json['title'],
      category: CollectionCategory.fromDbValue(
        json['category'] as String? ?? CollectionCategory.boardgame.dbValue,
      ),
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
      'image_url': imageUrl,
      'is_wishlist': isWishlist,
      'location_user_id': isWishlist ? null : locationUserId,
      'min_players': minPlayers,
      'max_players': maxPlayers,
      'playing_time': playingTime,
    };
  }

  String? get listSubtitle {
    if (category == CollectionCategory.boardgame && playingTime != null) {
      return '$playingTime min';
    }
    return category.label;
  }
}
