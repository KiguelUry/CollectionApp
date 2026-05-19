import 'collection_category.dart';
import 'book_subcategory.dart';
import 'card_subcategory.dart';
import 'category_metadata.dart';
import 'item_condition.dart';
import 'item_tag.dart';

class CollectionItem {
  final String id;
  final String title;
  final CollectionCategory category;
  final String? subcategory;
  final Map<String, dynamic>? metadata;
  final String? imageUrl;
  final bool isWishlist;
  final bool isForSale;
  final bool isSold;
  final int quantity;
  final String? locationId;
  final String? locationLabel;
  final String? groupId;
  final String? groupName;
  final String? addedBy;
  final String? locationUserId;
  final String? loanedToId;
  final String? loanedToName;
  final DateTime? loanedAt;
  final int? minPlayers;
  final int? maxPlayers;
  final int? playingTime;
  final double? rating;
  final String? review;
  final double? purchasePrice;
  final String? condition;
  final int? gamesPlayed;
  final String? personalRules;
  final DateTime? createdAt;
  final List<ItemTag> tags;
  final String? seriesId;
  final String? volumeId;
  final bool isRead;

  CollectionItem({
    required this.id,
    required this.title,
    required this.category,
    this.subcategory,
    this.metadata,
    this.imageUrl,
    required this.isWishlist,
    this.isForSale = false,
    this.isSold = false,
    this.quantity = 1,
    this.locationId,
    this.locationLabel,
    this.groupId,
    this.groupName,
    this.addedBy,
    this.locationUserId,
    this.loanedToId,
    this.loanedToName,
    this.loanedAt,
    this.minPlayers,
    this.maxPlayers,
    this.playingTime,
    this.rating,
    this.review,
    this.purchasePrice,
    this.condition,
    this.gamesPlayed,
    this.personalRules,
    this.createdAt,
    this.tags = const [],
    this.seriesId,
    this.volumeId,
    this.isRead = false,
  });

  bool get isGroupOwned => groupId != null;

  bool get isOnLoan =>
      loanedToId != null ||
      (loanedToName != null && loanedToName!.trim().isNotEmpty);

  String get loaneeDisplayName {
    final name = loanedToName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Quelqu\'un';
  }

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
    final holder = json['location_holder'];
    if (holder is Map && holder['username'] != null) {
      locLabel = 'Chez ${holder['username']}';
    }

    String? gName;
    final grp = json['groups'];
    if (grp is Map) {
      gName = grp['name'] as String?;
    }

    String? loanedName = json['loaned_to_name'] as String?;
    final loanedProfile = json['loaned_to'];
    if (loanedProfile is Map) {
      loanedName = loanedProfile['username'] as String? ?? loanedName;
    }

    DateTime? loanedAt;
    final rawLoanedAt = json['loaned_at'];
    if (rawLoanedAt is String) {
      loanedAt = DateTime.tryParse(rawLoanedAt);
    }

    DateTime? createdAt;
    final rawCreated = json['created_at'];
    if (rawCreated is String) {
      createdAt = DateTime.tryParse(rawCreated);
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
      isForSale: json['is_for_sale'] as bool? ?? false,
      isSold: json['is_sold'] as bool? ?? false,
      quantity: (json['quantity'] as int?) ?? 1,
      locationId: json['location_id'] as String?,
      locationLabel: locLabel,
      groupId: json['group_id'] as String?,
      groupName: gName,
      addedBy: json['added_by'] as String?,
      locationUserId: json['location_user_id'],
      loanedToId: json['loaned_to_id'] as String?,
      loanedToName: loanedName,
      loanedAt: loanedAt,
      minPlayers: json['min_players'],
      maxPlayers: json['max_players'],
      playingTime: json['playing_time'],
      rating: _parseDouble(json['rating']),
      review: json['review'] as String?,
      purchasePrice: _parseDouble(json['purchase_price']),
      condition: json['condition'] as String?,
      gamesPlayed: json['games_played'] as int?,
      personalRules: json['personal_rules'] as String?,
      createdAt: createdAt,
      tags: ItemTag.parseListFromItemJson(json),
      seriesId: json['series_id'] as String?,
      volumeId: json['volume_id'] as String?,
      isRead: json['is_read'] as bool? ?? false,
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
      'is_for_sale': isForSale,
      'is_sold': isSold,
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
      'series_id': seriesId,
      'volume_id': volumeId,
      'is_read': isRead,
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
      'location_user_id': locationUserId,
      'group_id': groupId,
      'metadata': metadata ?? {},
      'is_for_sale': isForSale,
      'is_sold': isSold,
      'loaned_to_id': loanedToId,
      'loaned_to_name': loanedToName,
      'loaned_at': loanedAt?.toUtc().toIso8601String(),
      'is_wishlist': isWishlist,
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
    bool? isWishlist,
    bool? isForSale,
    bool? isSold,
    String? loanedToId,
    String? loanedToName,
    DateTime? loanedAt,
    bool clearLoan = false,
    bool clearRating = false,
    bool clearPurchasePrice = false,
    bool clearGamesPlayed = false,
    bool clearGroup = false,
    bool clearLocation = false,
    String? locationUserId,
    Map<String, dynamic>? metadata,
    List<ItemTag>? tags,
    String? seriesId,
    String? volumeId,
    bool? isRead,
    bool clearSeries = false,
  }) {
    return CollectionItem(
      id: id,
      title: title,
      category: category,
      subcategory: subcategory,
      metadata: metadata ?? this.metadata,
      imageUrl: imageUrl,
      isWishlist: isWishlist ?? this.isWishlist,
      isForSale: isForSale ?? this.isForSale,
      isSold: isSold ?? this.isSold,
      quantity: quantity ?? this.quantity,
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      locationLabel: clearLocation ? null : (locationLabel ?? this.locationLabel),
      groupId: clearGroup ? null : (groupId ?? this.groupId),
      groupName: clearGroup ? null : (groupName ?? this.groupName),
      addedBy: addedBy,
      locationUserId:
          clearLocation ? null : (locationUserId ?? this.locationUserId),
      loanedToId: clearLoan ? null : (loanedToId ?? this.loanedToId),
      loanedToName: clearLoan ? null : (loanedToName ?? this.loanedToName),
      loanedAt: clearLoan ? null : (loanedAt ?? this.loanedAt),
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
      createdAt: createdAt,
      tags: tags ?? this.tags,
      seriesId: clearSeries ? null : (seriesId ?? this.seriesId),
      volumeId: clearSeries ? null : (volumeId ?? this.volumeId),
      isRead: isRead ?? this.isRead,
    );
  }

  String? get createdAtLabel {
    final dt = createdAt;
    if (dt == null) return null;
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return 'Ajouté le $d/$m/${dt.year}';
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
    if (isGroupOwned) return groupName ?? 'Groupe';
    return 'Personnel';
  }

  List<String> get sharedGroupNames {
    final raw = metadata?['group_ids'];
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  String? get listSubtitle {
    final parts = <String>[];
    final base = CategoryMetadata.subtitle(this);
    if (base != null) parts.add(base);
    if (quantity > 1) parts.add('×$quantity');
    if (locationLabel != null) parts.add(locationLabel!);
    if (rating != null) parts.add('★ ${rating!.toStringAsFixed(1)}');
    if (isOnLoan) parts.add('Prêté → $loaneeDisplayName');
    if (isSold) parts.add('Vendu');
    if (isForSale && !isSold) parts.add('À vendre');
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
