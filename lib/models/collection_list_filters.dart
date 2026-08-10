import '../models/collection_item.dart';
import '../utils/boardgame_display.dart';
import '../utils/boardgame_genres.dart';
import '../utils/card_item_metadata.dart';
import '../utils/holder_filter.dart';
import '../utils/wishlist_market_metadata.dart';

enum CollectionSort {
  titleAsc,
  titleDesc,
  ratingDesc,
  bggRatingDesc,
  quantityDesc,
  estimatedValueAsc,
  genreAsc,
  locationAsc,
}

enum CollectionScopeFilter {
  all,
  personalOnly,
  groupOnly,
  onLoanOnly,
}

enum CollectionOwnershipView {
  all,
  personal,
  groups,
}

enum CollectionStatusFilter {
  all,
  onLoan,
  highlyRated,
  withLocation,
}

/// Filtres et tri pour les grilles de collection (inspiré BGG / Libib).
class CollectionListFilters {
  String searchQuery;
  CollectionSort sort;
  CollectionScopeFilter scope;
  CollectionStatusFilter status;
  String? locationId;
  String? tagId;
  /// Filtre « chez qui » (`user:…`, `custom:…`, `loan:…`).
  String? holderKey;
  /// Genres BGG (`boardgamecategory`), jeux de société uniquement.
  Set<String> boardgameGenres;
  CollectionOwnershipView ownershipView;
  /// Groupe unique pour le filtre Focus (prioritaire sur [groupIds]).
  String? focusGroupId;
  Set<String> groupIds;
  Set<String> cardRarities;
  Set<String> pokemonTypes;
  /// Sous-catégories cartes (pokemon, onepiece…) — vue « toutes les cartes ».
  Set<String> cardSubcategories;
  /// Tri « Ma note » : false = meilleures d'abord, true = moins bonnes d'abord.
  bool ratingAscending;
  /// Tri note communautaire : false = meilleures d'abord, true = moins bonnes d'abord.
  bool bggRatingAscending;
  /// Tri localisation : false = A→Z, true = Z→A.
  bool locationAscending;

  /// Wishlist perso : objets ajoutés par moi, même s'ils sont dans un groupe.
  bool wishlistMineOnly;
  String? wishlistMineUserId;

  CollectionListFilters({
    this.searchQuery = '',
    this.sort = CollectionSort.titleAsc,
    this.scope = CollectionScopeFilter.all,
    this.status = CollectionStatusFilter.all,
    this.locationId,
    this.tagId,
    this.holderKey,
    Set<String>? boardgameGenres,
    this.ownershipView = CollectionOwnershipView.all,
    this.focusGroupId,
    Set<String>? groupIds,
    Set<String>? cardRarities,
    Set<String>? pokemonTypes,
    Set<String>? cardSubcategories,
    this.ratingAscending = false,
    this.bggRatingAscending = false,
    this.locationAscending = false,
    this.wishlistMineOnly = false,
    this.wishlistMineUserId,
  })  : groupIds = groupIds ?? <String>{},
        boardgameGenres = boardgameGenres ?? <String>{},
        cardRarities = cardRarities ?? <String>{},
        pokemonTypes = pokemonTypes ?? <String>{},
        cardSubcategories = cardSubcategories ?? <String>{};

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty ||
      scope != CollectionScopeFilter.all ||
      status != CollectionStatusFilter.all ||
      locationId != null ||
      tagId != null ||
      holderKey != null ||
      ownershipView != CollectionOwnershipView.all ||
      focusGroupId != null ||
      groupIds.isNotEmpty ||
      boardgameGenres.isNotEmpty ||
      cardRarities.isNotEmpty ||
      pokemonTypes.isNotEmpty ||
      cardSubcategories.isNotEmpty ||
      wishlistMineOnly ||
      sort != CollectionSort.titleAsc;

  /// Filtres actifs hors tri (pour badge bouton Filtre).
  /// `wishlistMineOnly` est un scope par défaut wishlist, pas un filtre « utilisateur ».
  bool get hasActiveFilterCriteria =>
      searchQuery.trim().isNotEmpty ||
      scope != CollectionScopeFilter.all ||
      status != CollectionStatusFilter.all ||
      locationId != null ||
      tagId != null ||
      holderKey != null ||
      ownershipView != CollectionOwnershipView.all ||
      focusGroupId != null ||
      groupIds.isNotEmpty ||
      boardgameGenres.isNotEmpty ||
      cardRarities.isNotEmpty ||
      pokemonTypes.isNotEmpty ||
      cardSubcategories.isNotEmpty;

  CollectionListFilters copyWith({
    String? searchQuery,
    CollectionSort? sort,
    CollectionScopeFilter? scope,
    CollectionStatusFilter? status,
    String? locationId,
    String? tagId,
    String? holderKey,
    Set<String>? boardgameGenres,
    CollectionOwnershipView? ownershipView,
    String? focusGroupId,
    Set<String>? groupIds,
    bool clearFocusGroup = false,
    Set<String>? cardRarities,
    Set<String>? pokemonTypes,
    Set<String>? cardSubcategories,
    bool clearLocation = false,
    bool clearTag = false,
    bool clearHolder = false,
    bool clearBoardgameGenre = false,
    bool clearGroups = false,
    bool clearCardFilters = false,
    bool? ratingAscending,
    bool? bggRatingAscending,
    bool? locationAscending,
    bool? wishlistMineOnly,
    String? wishlistMineUserId,
    bool clearWishlistMine = false,
  }) {
    return CollectionListFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      ratingAscending: ratingAscending ?? this.ratingAscending,
      bggRatingAscending: bggRatingAscending ?? this.bggRatingAscending,
      locationAscending: locationAscending ?? this.locationAscending,
      scope: scope ?? this.scope,
      status: status ?? this.status,
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      tagId: clearTag ? null : (tagId ?? this.tagId),
      holderKey: clearHolder ? null : (holderKey ?? this.holderKey),
      ownershipView: ownershipView ?? this.ownershipView,
      focusGroupId:
          clearFocusGroup ? null : (focusGroupId ?? this.focusGroupId),
      groupIds: clearGroups ? <String>{} : (groupIds ?? this.groupIds),
      boardgameGenres: clearBoardgameGenre
          ? <String>{}
          : (boardgameGenres ?? this.boardgameGenres),
      cardRarities: clearCardFilters
          ? <String>{}
          : (cardRarities ?? this.cardRarities),
      pokemonTypes: clearCardFilters
          ? <String>{}
          : (pokemonTypes ?? this.pokemonTypes),
      cardSubcategories: clearCardFilters
          ? <String>{}
          : (cardSubcategories ?? this.cardSubcategories),
      wishlistMineOnly: clearWishlistMine
          ? false
          : (wishlistMineOnly ?? this.wishlistMineOnly),
      wishlistMineUserId: clearWishlistMine
          ? null
          : (wishlistMineUserId ?? this.wishlistMineUserId),
    );
  }

  List<CollectionItem> apply(List<CollectionItem> items) {
    var result = List<CollectionItem>.from(items);

    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result
          .where((i) => i.title.toLowerCase().contains(q))
          .toList();
    }

    if (locationId != null) {
      result = result.where((i) => i.locationId == locationId).toList();
    }

    if (holderKey != null) {
      result =
          result.where((i) => itemMatchesHolderKey(i, holderKey)).toList();
    }

    if (tagId != null) {
      result = result.where((i) => i.tags.any((t) => t.id == tagId)).toList();
    }

    if (boardgameGenres.isNotEmpty) {
      result = result
          .where(
            (i) => boardgameGenresFromMetadata(i.metadata).any(
              (g) => boardgameGenres.any(
                (selected) => selected.toLowerCase() == g.toLowerCase(),
              ),
            ),
          )
          .toList();
    }

    if (cardRarities.isNotEmpty) {
      result = result.where((i) {
        final r = cardRarityFromMetadata(i.metadata);
        return r != null &&
            cardRarities.any((s) => s.toLowerCase() == r.toLowerCase());
      }).toList();
    }

    if (pokemonTypes.isNotEmpty) {
      result = result.where((i) {
        final types = pokemonTypesFromMetadata(i.metadata);
        return types.any(
          (t) => pokemonTypes.any((s) => s.toLowerCase() == t.toLowerCase()),
        );
      }).toList();
    }

    if (cardSubcategories.isNotEmpty) {
      result = result
          .where(
            (i) =>
                i.subcategory != null &&
                cardSubcategories.contains(i.subcategory),
          )
          .toList();
    }

    if (focusGroupId != null && focusGroupId!.isNotEmpty) {
      result = result.where((i) => i.groupId == focusGroupId).toList();
    } else if (wishlistMineOnly && wishlistMineUserId != null) {
      final uid = wishlistMineUserId!;
      result = result
          .where((i) => i.addedBy == uid || i.groupId == null)
          .toList();
    } else if (ownershipView == CollectionOwnershipView.personal) {
      result = result.where((i) => !i.isGroupOwned).toList();
    } else if (ownershipView == CollectionOwnershipView.groups) {
      result = result.where((i) => i.isGroupOwned).toList();
      if (groupIds.isNotEmpty) {
        result = result.where((i) => groupIds.contains(i.groupId)).toList();
      }
    }

    switch (scope) {
      case CollectionScopeFilter.all:
      case CollectionScopeFilter.personalOnly:
      case CollectionScopeFilter.groupOnly:
        break;
      case CollectionScopeFilter.onLoanOnly:
        result = result.where((i) => i.isOnLoan).toList();
    }

    switch (status) {
      case CollectionStatusFilter.all:
        break;
      case CollectionStatusFilter.onLoan:
        break;
      case CollectionStatusFilter.highlyRated:
        result = result.where((i) => (i.rating ?? 0) >= 4).toList();
      case CollectionStatusFilter.withLocation:
        result = result
            .where((i) => i.locationId != null && i.locationId!.isNotEmpty)
            .toList();
    }

    result.sort(_comparator);
    return result;
  }

  int _comparator(CollectionItem a, CollectionItem b) {
    switch (sort) {
      case CollectionSort.titleAsc:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case CollectionSort.titleDesc:
        return b.title.toLowerCase().compareTo(a.title.toLowerCase());
      case CollectionSort.ratingDesc:
        final ra = a.rating ?? -1;
        final rb = b.rating ?? -1;
        final cmp = ratingAscending ? ra.compareTo(rb) : rb.compareTo(ra);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.bggRatingDesc:
        final ra = parseBggAvgRating(a.metadata?['bgg_avg_rating']) ?? -1;
        final rb = parseBggAvgRating(b.metadata?['bgg_avg_rating']) ?? -1;
        final cmp =
            bggRatingAscending ? ra.compareTo(rb) : rb.compareTo(ra);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.quantityDesc:
        final cmp = b.quantity.compareTo(a.quantity);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.estimatedValueAsc:
        final va = marketSecondhandPriceFromMetadata(a.metadata) ??
            marketNewPriceMinFromMetadata(a.metadata) ??
            double.infinity;
        final vb = marketSecondhandPriceFromMetadata(b.metadata) ??
            marketNewPriceMinFromMetadata(b.metadata) ??
            double.infinity;
        final cmp = va.compareTo(vb);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.genreAsc:
        final ga = primaryBoardgameGenre(a) ?? 'zzz';
        final gb = primaryBoardgameGenre(b) ?? 'zzz';
        final cmp = ga.toLowerCase().compareTo(gb.toLowerCase());
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.locationAsc:
        final la = holderLabelForItem(a).toLowerCase();
        final lb = holderLabelForItem(b).toLowerCase();
        final cmp = locationAscending ? lb.compareTo(la) : la.compareTo(lb);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
    }
  }
}
