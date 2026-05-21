import '../models/collection_item.dart';
import '../utils/boardgame_genres.dart';
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
  /// Genre BGG (`boardgamecategory`), jeux de société uniquement.
  String? boardgameGenre;

  CollectionListFilters({
    this.searchQuery = '',
    this.sort = CollectionSort.titleAsc,
    this.scope = CollectionScopeFilter.all,
    this.status = CollectionStatusFilter.all,
    this.locationId,
    this.tagId,
    this.holderKey,
    this.boardgameGenre,
  });

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty ||
      scope != CollectionScopeFilter.all ||
      status != CollectionStatusFilter.all ||
      locationId != null ||
      tagId != null ||
      holderKey != null ||
      boardgameGenre != null ||
      sort != CollectionSort.titleAsc;

  CollectionListFilters copyWith({
    String? searchQuery,
    CollectionSort? sort,
    CollectionScopeFilter? scope,
    CollectionStatusFilter? status,
    String? locationId,
    String? tagId,
    String? holderKey,
    String? boardgameGenre,
    bool clearLocation = false,
    bool clearTag = false,
    bool clearHolder = false,
    bool clearBoardgameGenre = false,
  }) {
    return CollectionListFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      scope: scope ?? this.scope,
      status: status ?? this.status,
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      tagId: clearTag ? null : (tagId ?? this.tagId),
      holderKey: clearHolder ? null : (holderKey ?? this.holderKey),
      boardgameGenre: clearBoardgameGenre
          ? null
          : (boardgameGenre ?? this.boardgameGenre),
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

    if (boardgameGenre != null && boardgameGenre!.isNotEmpty) {
      final genre = boardgameGenre!;
      result = result
          .where(
            (i) => boardgameGenresFromMetadata(i.metadata)
                .any((g) => g.toLowerCase() == genre.toLowerCase()),
          )
          .toList();
    }

    switch (scope) {
      case CollectionScopeFilter.all:
        break;
      case CollectionScopeFilter.personalOnly:
        result = result.where((i) => !i.isGroupOwned).toList();
      case CollectionScopeFilter.groupOnly:
        result = result.where((i) => i.isGroupOwned).toList();
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
