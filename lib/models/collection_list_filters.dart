import '../models/collection_item.dart';
import '../utils/boardgame_genres.dart';
import '../utils/card_item_metadata.dart';
import '../utils/holder_filter.dart';

enum CollectionSort {
  titleAsc,
  titleDesc,
  ratingDesc,
  quantityDesc,
  newestFirst,
  oldestFirst,
  genreAsc,
}

enum CollectionScopeFilter {
  all,
  personalOnly,
  groupOnly,
  onLoanOnly,
}

enum CollectionOwnershipView {
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
  Set<String> groupIds;
  Set<String> cardRarities;
  Set<String> pokemonTypes;

  CollectionListFilters({
    this.searchQuery = '',
    this.sort = CollectionSort.titleAsc,
    this.scope = CollectionScopeFilter.all,
    this.status = CollectionStatusFilter.all,
    this.locationId,
    this.tagId,
    this.holderKey,
    Set<String>? boardgameGenres,
    this.ownershipView = CollectionOwnershipView.personal,
    Set<String>? groupIds,
    Set<String>? cardRarities,
    Set<String>? pokemonTypes,
  })  : groupIds = groupIds ?? <String>{},
        boardgameGenres = boardgameGenres ?? <String>{},
        cardRarities = cardRarities ?? <String>{},
        pokemonTypes = pokemonTypes ?? <String>{};

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty ||
      scope != CollectionScopeFilter.all ||
      status != CollectionStatusFilter.all ||
      locationId != null ||
      tagId != null ||
      holderKey != null ||
      groupIds.isNotEmpty ||
      boardgameGenres.isNotEmpty ||
      cardRarities.isNotEmpty ||
      pokemonTypes.isNotEmpty ||
      sort != CollectionSort.titleAsc;

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
    Set<String>? groupIds,
    Set<String>? cardRarities,
    Set<String>? pokemonTypes,
    bool clearLocation = false,
    bool clearTag = false,
    bool clearHolder = false,
    bool clearBoardgameGenre = false,
    bool clearGroups = false,
    bool clearCardFilters = false,
  }) {
    return CollectionListFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      scope: scope ?? this.scope,
      status: status ?? this.status,
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      tagId: clearTag ? null : (tagId ?? this.tagId),
      holderKey: clearHolder ? null : (holderKey ?? this.holderKey),
      ownershipView: ownershipView ?? this.ownershipView,
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

    if (ownershipView == CollectionOwnershipView.personal) {
      result = result.where((i) => !i.isGroupOwned).toList();
    } else {
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
        final cmp = rb.compareTo(ra);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.quantityDesc:
        final cmp = b.quantity.compareTo(a.quantity);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.newestFirst:
        final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = db.compareTo(da);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.oldestFirst:
        final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = da.compareTo(db);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.genreAsc:
        final ga = primaryBoardgameGenre(a) ?? 'zzz';
        final gb = primaryBoardgameGenre(b) ?? 'zzz';
        final cmp = ga.toLowerCase().compareTo(gb.toLowerCase());
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
    }
  }
}
