import 'collection_category.dart';
import 'book_subcategory.dart';
import 'card_subcategory.dart';
import 'category_metadata.dart';
import 'item_condition.dart';

class CollectionItem {
  final String id;
  final String title;
  final CollectionCategory category;
  final String? subcategory;
  final Map<String, dynamic>? metadata;
  final String? imageUrl;
  final bool isWishlist;
  final int quantity;
  final String? locationId;
  final String? locationLabel;
  final String? groupId;
  final String? groupName;
  final String? addedBy;
  final String? locationUserId;
  final String? loanedToId;
  final String? loanedToName;
  final int? minPlayers;
  final int? maxPlayers;
  final int? playingTime;
  final double? rating;
  final String? review;
  final double? purchasePrice;
  final String? condition;
  final int? gamesPlayed;
  final String? personalRules;

  CollectionItem({
    required this.id,
    required this.title,
    required this.category,
    this.subcategory,
    this.metadata,
    this.imageUrl,
    required this.isWishlist,
    this.quantity = 1,
    this.locationId,
    this.locationLabel,
    this.groupId,
    this.groupName,
    this.addedBy,
    this.locationUserId,
    this.loanedToId,
    this.loanedToName,
    this.minPlayers,
    this.maxPlayers,
    this.playingTime,
    this.rating,
    this.review,
    this.purchasePrice,
    this.condition,
    this.gamesPlayed,
    this.personalRules,
  });

  bool get isGroupOwned => groupId != null;

  factory CollectionItem.fromJson(Map<String, dynamic> json) {
    final category = CollectionCategory.fromDbValue(
      json['category'] as String? ?? CollectionCategory.boardgame.dbValue,
    );
    final rawSub = json['subcategory'] as String?;

    String? locLabel;
    final loc = json['locations'];
    if (loc is Map) {
      locLabel = loc['label'] as String?;
    }

    String? gName;
    final grp = json['groups'];
    if (grp is Map) {
      gName = grp['name'] as String?;
    }

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
      quantity: (json['quantity'] as int?) ?? 1,
      locationId: json['location_id'] as String?,
      locationLabel: locLabel,
      groupId: json['group_id'] as String?,
      groupName: gName,
      addedBy: json['added_by'] as String?,
      locationUserId: json['location_user_id'],
      loanedToId: json['loaned_to_id'],
      loanedToName: json['loaned_to_name'],
      minPlayers: json['min_players'],
      maxPlayers: json['max_players'],
      playingTime: json['playing_time'],
      rating: _parseDouble(json['rating']),
      review: json['review'] as String?,
      purchasePrice: _parseDouble(json['purchase_price']),
      condition: json['condition'] as String?,
      gamesPlayed: json['games_played'] as int?,
      personalRules: json['personal_rules'] as String?,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Map<String, dynamic> toInsertJson({
    required bool isWishlist,
    String? locationUserId,
    String? addedBy,
  }) {
    return {
      'title': title,
      'category': category.dbValue,
      'subcategory': subcategory,
      'metadata': metadata ?? {},
      'image_url': imageUrl,
      'is_wishlist': isWishlist,
      'quantity': quantity,
      'location_id': locationId,
      'group_id': groupId,
      'added_by': addedBy,
      'location_user_id': isWishlist ? null : locationUserId,
      'min_players': minPlayers,
      'max_players': maxPlayers,
      'playing_time': playingTime,
      'rating': rating,
      'review': review,
      'purchase_price': purchasePrice,
      'condition': condition,
      'games_played': gamesPlayed,
      'personal_rules': personalRules,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'rating': rating,
      'review': review?.trim().isEmpty == true ? null : review?.trim(),
      'purchase_price': purchasePrice,
      'condition': condition,
      'games_played': gamesPlayed,
      'personal_rules':
          personalRules?.trim().isEmpty == true ? null : personalRules?.trim(),
      'quantity': quantity,
      'location_id': locationId,
      'group_id': groupId,
    };
  }

  CollectionItem copyWith({
    int? quantity,
    String? locationId,
    String? locationLabel,
    String? groupId,
    String? groupName,
    double? rating,
    String? review,
    double? purchasePrice,
    String? condition,
    int? gamesPlayed,
    String? personalRules,
    bool clearRating = false,
    bool clearPurchasePrice = false,
    bool clearGamesPlayed = false,
    bool clearGroup = false,
    bool clearLocation = false,
  }) {
    return CollectionItem(
      id: id,
      title: title,
      category: category,
      subcategory: subcategory,
      metadata: metadata,
      imageUrl: imageUrl,
      isWishlist: isWishlist,
      quantity: quantity ?? this.quantity,
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      locationLabel: clearLocation ? null : (locationLabel ?? this.locationLabel),
      groupId: clearGroup ? null : (groupId ?? this.groupId),
      groupName: clearGroup ? null : (groupName ?? this.groupName),
      addedBy: addedBy,
      locationUserId: locationUserId,
      loanedToId: loanedToId,
      loanedToName: loanedToName,
      minPlayers: minPlayers,
      maxPlayers: maxPlayers,
      playingTime: playingTime,
      rating: clearRating ? null : (rating ?? this.rating),
      review: review ?? this.review,
      purchasePrice:
          clearPurchasePrice ? null : (purchasePrice ?? this.purchasePrice),
      condition: condition ?? this.condition,
      gamesPlayed: clearGamesPlayed ? null : (gamesPlayed ?? this.gamesPlayed),
      personalRules: personalRules ?? this.personalRules,
    );
  }

  BookSubcategory? get bookSubcategory {
    if (category != CollectionCategory.book) return null;
    return BookSubcategory.fromDbValue(subcategory);
  }

  CardSubcategory? get cardSubcategory {
    if (category != CollectionCategory.card) return null;
    return CardSubcategory.fromDbValue(subcategory);
  }

  ItemCondition? get itemCondition => ItemCondition.fromDbValue(condition);

  String? get ownershipLabel {
    if (isGroupOwned) return 'Famille / ${groupName ?? 'groupe'}';
    return 'Personnel';
  }

  String? get listSubtitle {
    final parts = <String>[];
    final base = CategoryMetadata.subtitle(this);
    if (base != null) parts.add(base);
    if (quantity > 1) parts.add('×$quantity');
    if (locationLabel != null) parts.add(locationLabel!);
    if (rating != null) parts.add('★ ${rating!.toStringAsFixed(1)}');
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
