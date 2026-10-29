import 'collection_category.dart';
import 'book_subcategory.dart';
import 'card_subcategory.dart';
import 'category_metadata.dart';
import 'item_condition.dart';
import 'item_tag.dart';
import '../utils/display_text.dart';
import '../utils/holder_label_utils.dart';

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
  final bool isExpansion;
  final String? parentGameId;

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
    this.quantity = 0,
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
    this.isExpansion = false,
    this.parentGameId,
  });

  /// Nom du jeu de base (extensions orphelines).
  String? get parentGameTitle =>
      metadata?['expansion_of_title']?.toString() ??
      metadata?['base_game_title']?.toString();

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
      json['category']?.toString() ?? CollectionCategory.boardgame.dbValue,
    );
    final rawSub = json['subcategory']?.toString();

    String? locLabel;
    final loc = json['locations'];
    if (loc is Map) {
      locLabel = loc['label']?.toString();
    }
    final holder = json['location_holder'];
    final locationUserId = json['location_user_id']?.toString();

    String? gName;
    final grp = json['groups'];
    if (grp is Map) {
      gName = grp['name']?.toString();
    }

    String? loanedName = json['loaned_to_name']?.toString();
    final loanedProfile = json['loaned_to'];
    if (loanedProfile is Map) {
      loanedName = loanedProfile['username']?.toString() ?? loanedName;
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

    var metadata = CategoryMetadata.parse(json['metadata']);

    final customHolder = metadata?['holder_label']?.toString();
    final hasCustomHolder =
        customHolder != null && customHolder.trim().isNotEmpty;

    if (locationUserId != null &&
        locationUserId.isNotEmpty &&
        holder is Map &&
        holder['username'] != null) {
      locLabel = 'Chez ${holder['username']}';
    } else if (hasCustomHolder) {
      locLabel = formatManualHolderLabel(customHolder.trim());
    } else if (locLabel == null && loc is Map) {
      locLabel = loc['label']?.toString();
    }

    // Conserve le username d'ajout pour l'UI (groupes / historique).
    final addedByProfile = json['added_by_profile'] ??
        json['profiles'] ??
        json['profiles!collection_items_added_by_fkey'];
    if (addedByProfile is Map && addedByProfile['username'] != null) {
      metadata = Map<String, dynamic>.from(metadata ?? {});
      metadata['_added_by_username'] = addedByProfile['username'].toString();
    }

    final rawDesc = metadata?['bgg_description']?.toString() ??
        metadata?['description']?.toString();
    if (rawDesc != null && rawDesc.contains('&')) {
      metadata = Map<String, dynamic>.from(metadata ?? {});
      if (metadata['bgg_description'] != null) {
        metadata['bgg_description'] =
            cleanDisplayText(metadata['bgg_description']?.toString());
      }
      if (metadata['description'] != null) {
        metadata['description'] =
            cleanDisplayText(metadata['description']?.toString());
      }
      if (metadata['bgg_short_description'] != null) {
        metadata['bgg_short_description'] =
            cleanDisplayText(metadata['bgg_short_description']?.toString());
      }
    }

    return CollectionItem(
      id: json['id']?.toString() ?? '',
      title: cleanDisplayText(json['title']?.toString()),
      category: category,
      subcategory: category == CollectionCategory.book
          ? (rawSub ?? (json['category']?.toString() == 'manga' ? 'manga' : null))
          : rawSub,
      metadata: metadata,
      imageUrl: _resolveImageUrl(json),
      isWishlist: _flag(json['is_wishlist']),
      isForSale: _flag(json['is_for_sale']),
      isSold: _flag(json['is_sold']),
      quantity: _int(json['quantity']) ?? 0,
      locationId: json['location_id']?.toString(),
      locationLabel: locLabel,
      groupId: json['group_id']?.toString(),
      groupName: gName,
      addedBy: json['added_by']?.toString(),
      locationUserId: json['location_user_id']?.toString(),
      loanedToId: json['loaned_to_id']?.toString(),
      loanedToName: loanedName,
      loanedAt: loanedAt,
      minPlayers: _int(json['min_players']),
      maxPlayers: _int(json['max_players']),
      playingTime: _int(json['playing_time']),
      rating: _parseDouble(json['rating']),
      review: json['review']?.toString(),
      purchasePrice: _parseDouble(json['purchase_price']),
      condition: json['condition']?.toString(),
      gamesPlayed: _int(json['games_played']),
      personalRules: json['personal_rules']?.toString(),
      createdAt: createdAt,
      tags: ItemTag.parseListFromItemJson(json),
      seriesId: json['series_id']?.toString(),
      volumeId: json['volume_id']?.toString(),
      isRead: _flag(json['is_read']),
      isExpansion: _flag(json['is_expansion']) ||
          metadata?['bgg_is_expansion'] == true,
      parentGameId: json['parent_game_id']?.toString(),
    );
  }

  static bool _flag(dynamic v) =>
      v == true || v == 1 || v == 'true' || v == '1';

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString());
  }

  static String? _resolveImageUrl(Map<String, dynamic> json) {
    final direct = json['image_url']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final meta = json['metadata'];
    if (meta is Map) {
      final fromMeta = meta['image_url']?.toString().trim();
      if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
    }
    return null;
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
      'playing_time':
          playingTime != null && playingTime! > 0 ? playingTime : null,
      'rating': rating,
      'review': review,
      'purchase_price': purchasePrice,
      'condition': condition,
      'games_played': gamesPlayed,
      'personal_rules': personalRules,
      'series_id': seriesId,
      'volume_id': volumeId,
      'is_read': isRead,
      'is_expansion': isExpansion,
      if (parentGameId != null) 'parent_game_id': parentGameId,
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
    bool clearLocationUserId = false,
    String? locationUserId,
    int? minPlayers,
    int? maxPlayers,
    int? playingTime,
    Map<String, dynamic>? metadata,
    List<ItemTag>? tags,
    String? seriesId,
    String? volumeId,
    bool? isRead,
    bool clearSeries = false,
    bool? isExpansion,
    String? parentGameId,
    bool clearParentGame = false,
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
      locationUserId: clearLocation || clearLocationUserId
          ? null
          : (locationUserId ?? this.locationUserId),
      loanedToId: clearLoan ? null : (loanedToId ?? this.loanedToId),
      loanedToName: clearLoan ? null : (loanedToName ?? this.loanedToName),
      loanedAt: clearLoan ? null : (loanedAt ?? this.loanedAt),
      minPlayers: minPlayers ?? this.minPlayers,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      playingTime: playingTime ?? this.playingTime,
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
      isExpansion: isExpansion ?? this.isExpansion,
      parentGameId:
          clearParentGame ? null : (parentGameId ?? this.parentGameId),
    );
  }

  String? get createdAtLabel {
    final dt = createdAt;
    if (dt == null) return null;
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return 'Ajouté le $d/$m/${dt.year}';
  }

  /// Favori local (metadata, pas la vitrine profil limitée à 6).
  bool get isFavorite => metadata?['is_favorite'] == true;

  CollectionItem withFavorite(bool value) {
    final meta = Map<String, dynamic>.from(metadata ?? {});
    if (value) {
      meta['is_favorite'] = true;
    } else {
      meta.remove('is_favorite');
    }
    return copyWith(metadata: meta);
  }

  /// Username de l'ajouteur si l'embed `profiles!…added_by…` est présent.
  String? get addedByUsername {
    final raw = metadata?['_added_by_username']?.toString().trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return null;
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
