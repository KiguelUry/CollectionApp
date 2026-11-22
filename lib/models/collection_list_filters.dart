import '../models/boardgame_play_session.dart';
import '../models/collection_item.dart';
import '../utils/boardgame_display.dart';
import '../utils/boardgame_genres.dart';
import '../utils/card_item_metadata.dart';
import '../utils/holder_filter.dart';
import '../utils/item_search.dart';
import '../utils/videogame_metadata.dart';
import '../utils/wishlist_market_metadata.dart';
import '../models/videogame_platform.dart';

enum CollectionSort {
  titleAsc,
  titleDesc,
  ratingDesc,
  bggRatingDesc,
  quantityDesc,
  estimatedValueAsc,
  estimatedValueDesc,
  genreAsc,
  locationAsc,
  favoritesFirst,
  playsDesc,
  costPerPlayAsc,
  durationAsc,
  complexityAsc,
  yearDesc,
  dateAddedDesc,
}

enum BoardgamePlayStatusFilter {
  any,
  neverPlayed,
  played,
  staleSixMonths,
}

enum BoardgameComplexityBand {
  familial,
  intermediate,
  expert,
}

enum BoardgameDurationBucket {
  under30,
  from30to60,
  from1hTo2h,
  over2h,
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
  /// Plateformes jeux vidéo (`platform_ids` dans metadata).
  Set<String> videogamePlatforms;
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
  /// N'afficher que les favoris (cœur).
  bool favoritesOnly;
  /// Jeux jamais joués (0 partie) — « pile de la honte ».
  bool unplayedOnly;

  /// Filtres jeux de société avancés.
  Set<int> playerCounts;
  bool playerCountBestOnly;
  Set<BoardgameDurationBucket> durationBuckets;
  Set<BoardgameComplexityBand> complexityBands;
  BoardgamePlayStatusFilter playStatus;
  bool forSaleOrTradeOnly;
  bool withExpansionsOnly;
  bool withCustomRulesOnly;

  CollectionListFilters({
    this.searchQuery = '',
    this.sort = CollectionSort.titleAsc,
    this.scope = CollectionScopeFilter.all,
    this.status = CollectionStatusFilter.all,
    this.locationId,
    this.tagId,
    this.holderKey,
    Set<String>? boardgameGenres,
    Set<String>? videogamePlatforms,
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
    this.favoritesOnly = false,
    this.unplayedOnly = false,
    Set<int>? playerCounts,
    this.playerCountBestOnly = false,
    Set<BoardgameDurationBucket>? durationBuckets,
    Set<BoardgameComplexityBand>? complexityBands,
    this.playStatus = BoardgamePlayStatusFilter.any,
    this.forSaleOrTradeOnly = false,
    this.withExpansionsOnly = false,
    this.withCustomRulesOnly = false,
  })  : groupIds = groupIds ?? <String>{},
        boardgameGenres = boardgameGenres ?? <String>{},
        videogamePlatforms = videogamePlatforms ?? <String>{},
        cardRarities = cardRarities ?? <String>{},
        pokemonTypes = pokemonTypes ?? <String>{},
        cardSubcategories = cardSubcategories ?? <String>{},
        playerCounts = playerCounts ?? <int>{},
        durationBuckets = durationBuckets ?? <BoardgameDurationBucket>{},
        complexityBands = complexityBands ?? <BoardgameComplexityBand>{};

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
      videogamePlatforms.isNotEmpty ||
      cardRarities.isNotEmpty ||
      pokemonTypes.isNotEmpty ||
      cardSubcategories.isNotEmpty ||
      wishlistMineOnly ||
      favoritesOnly ||
      unplayedOnly ||
      playerCounts.isNotEmpty ||
      durationBuckets.isNotEmpty ||
      complexityBands.isNotEmpty ||
      playStatus != BoardgamePlayStatusFilter.any ||
      forSaleOrTradeOnly ||
      withExpansionsOnly ||
      withCustomRulesOnly ||
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
      videogamePlatforms.isNotEmpty ||
      cardRarities.isNotEmpty ||
      pokemonTypes.isNotEmpty ||
      cardSubcategories.isNotEmpty ||
      favoritesOnly ||
      unplayedOnly ||
      playerCounts.isNotEmpty ||
      durationBuckets.isNotEmpty ||
      complexityBands.isNotEmpty ||
      playStatus != BoardgamePlayStatusFilter.any ||
      forSaleOrTradeOnly ||
      withExpansionsOnly ||
      withCustomRulesOnly;

  CollectionListFilters copyWith({
    String? searchQuery,
    CollectionSort? sort,
    CollectionScopeFilter? scope,
    CollectionStatusFilter? status,
    String? locationId,
    String? tagId,
    String? holderKey,
    Set<String>? boardgameGenres,
    Set<String>? videogamePlatforms,
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
    bool clearVideogamePlatform = false,
    bool clearGroups = false,
    bool clearCardFilters = false,
    bool? ratingAscending,
    bool? bggRatingAscending,
    bool? locationAscending,
    bool? wishlistMineOnly,
    String? wishlistMineUserId,
    bool clearWishlistMine = false,
    bool? favoritesOnly,
    bool? unplayedOnly,
    Set<int>? playerCounts,
    bool? playerCountBestOnly,
    Set<BoardgameDurationBucket>? durationBuckets,
    Set<BoardgameComplexityBand>? complexityBands,
    BoardgamePlayStatusFilter? playStatus,
    bool? forSaleOrTradeOnly,
    bool? withExpansionsOnly,
    bool? withCustomRulesOnly,
    bool clearBoardgameAdvanced = false,
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
      videogamePlatforms: clearVideogamePlatform
          ? <String>{}
          : (videogamePlatforms ?? this.videogamePlatforms),
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
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      unplayedOnly: unplayedOnly ?? this.unplayedOnly,
      playerCounts: clearBoardgameAdvanced
          ? <int>{}
          : (playerCounts ?? this.playerCounts),
      playerCountBestOnly: clearBoardgameAdvanced
          ? false
          : (playerCountBestOnly ?? this.playerCountBestOnly),
      durationBuckets: clearBoardgameAdvanced
          ? <BoardgameDurationBucket>{}
          : (durationBuckets ?? this.durationBuckets),
      complexityBands: clearBoardgameAdvanced
          ? <BoardgameComplexityBand>{}
          : (complexityBands ?? this.complexityBands),
      playStatus: clearBoardgameAdvanced
          ? BoardgamePlayStatusFilter.any
          : (playStatus ?? this.playStatus),
      forSaleOrTradeOnly: clearBoardgameAdvanced
          ? false
          : (forSaleOrTradeOnly ?? this.forSaleOrTradeOnly),
      withExpansionsOnly: clearBoardgameAdvanced
          ? false
          : (withExpansionsOnly ?? this.withExpansionsOnly),
      withCustomRulesOnly: clearBoardgameAdvanced
          ? false
          : (withCustomRulesOnly ?? this.withCustomRulesOnly),
    );
  }

  /// Parties enregistrées (historique détaillé, sinon compteur manuel).
  static int playCountOf(CollectionItem item) {
    final sessions = parseBoardgamePlays(item.metadata).length;
    if (sessions > 0) return sessions;
    return item.gamesPlayed ?? 0;
  }

  static int? playingTimeOf(CollectionItem item) {
    final raw = item.playingTime ??
        int.tryParse('${item.metadata?['playing_time'] ?? ''}');
    return raw != null && raw > 0 ? raw : null;
  }

  static double? complexityOf(CollectionItem item) {
    final raw = item.metadata?['bgg_weight'] ??
        item.metadata?['averageweight'] ??
        item.metadata?['avgweight'];
    return double.tryParse('$raw');
  }

  static int? yearOf(CollectionItem item) {
    final raw = item.metadata?['year'] ?? item.metadata?['yearpublished'];
    return int.tryParse('$raw');
  }

  static DateTime? lastPlayAt(CollectionItem item) {
    DateTime? latest;
    for (final p in parseBoardgamePlays(item.metadata)) {
      if (latest == null || p.date.isAfter(latest)) latest = p.date;
    }
    return latest;
  }

  static bool matchesPlayerCount(
    CollectionItem item,
    int count, {
    required bool bestOnly,
  }) {
    if (bestOnly) {
      final best = item.metadata?['bgg_best_players'];
      if (best is List) {
        return best.any((v) => int.tryParse('$v') == count);
      }
      final s = best?.toString() ?? '';
      return RegExp(r'\b$count\b'.replaceFirst(r'$count', '$count'))
          .hasMatch(s);
    }
    final min = item.minPlayers;
    final max = item.maxPlayers;
    if (min == null && max == null) return false;
    if (count >= 6) {
      final top = max ?? min ?? 0;
      return top >= 6;
    }
    final lo = min ?? 1;
    final hi = max ?? lo;
    return count >= lo && count <= hi;
  }

  static bool matchesDuration(
    CollectionItem item,
    Set<BoardgameDurationBucket> buckets,
  ) {
    final t = playingTimeOf(item);
    if (t == null) return false;
    for (final b in buckets) {
      final ok = switch (b) {
        BoardgameDurationBucket.under30 => t < 30,
        BoardgameDurationBucket.from30to60 => t >= 30 && t <= 60,
        BoardgameDurationBucket.from1hTo2h => t > 60 && t <= 120,
        BoardgameDurationBucket.over2h => t > 120,
      };
      if (ok) return true;
    }
    return false;
  }

  static bool matchesComplexity(
    CollectionItem item,
    Set<BoardgameComplexityBand> bands,
  ) {
    final w = complexityOf(item);
    if (w == null) return false;
    for (final b in bands) {
      final ok = switch (b) {
        BoardgameComplexityBand.familial => w < 2.0,
        BoardgameComplexityBand.intermediate => w >= 2.0 && w < 3.2,
        BoardgameComplexityBand.expert => w >= 3.2,
      };
      if (ok) return true;
    }
    return false;
  }

  List<CollectionItem> apply(List<CollectionItem> items) {
    var result = List<CollectionItem>.from(items);

    if (searchQuery.trim().isNotEmpty) {
      result = result
          .where((i) => itemMatchesSearch(i, searchQuery))
          .toList();
    }

    if (favoritesOnly) {
      result = result.where((i) => i.isFavorite).toList();
    }

    if (unplayedOnly) {
      result = result.where((i) => playCountOf(i) == 0).toList();
    }

    if (playerCounts.isNotEmpty) {
      result = result
          .where(
            (i) => playerCounts.any(
              (c) => matchesPlayerCount(
                i,
                c,
                bestOnly: playerCountBestOnly,
              ),
            ),
          )
          .toList();
    }

    if (durationBuckets.isNotEmpty) {
      result =
          result.where((i) => matchesDuration(i, durationBuckets)).toList();
    }

    if (complexityBands.isNotEmpty) {
      result =
          result.where((i) => matchesComplexity(i, complexityBands)).toList();
    }

    switch (playStatus) {
      case BoardgamePlayStatusFilter.any:
        break;
      case BoardgamePlayStatusFilter.neverPlayed:
        result = result.where((i) => playCountOf(i) == 0).toList();
      case BoardgamePlayStatusFilter.played:
        result = result.where((i) => playCountOf(i) > 0).toList();
      case BoardgamePlayStatusFilter.staleSixMonths:
        final cutoff = DateTime.now().subtract(const Duration(days: 183));
        result = result.where((i) {
          if (playCountOf(i) == 0) return true;
          final last = lastPlayAt(i);
          return last == null || last.isBefore(cutoff);
        }).toList();
    }

    if (forSaleOrTradeOnly) {
      result = result
          .where(
            (i) =>
                i.isForSale ||
                i.metadata?['for_trade'] == true ||
                i.metadata?['to_trade'] == true,
          )
          .toList();
    }

    if (withExpansionsOnly) {
      result = result.where((i) {
        final ex = i.metadata?['expansions'] ?? i.metadata?['owned_expansions'];
        if (ex is List) return ex.isNotEmpty;
        return (i.metadata?['expansion_count'] as num?)?.toInt() != null &&
            ((i.metadata?['expansion_count'] as num?)?.toInt() ?? 0) > 0;
      }).toList();
    }

    if (withCustomRulesOnly) {
      result = result.where((i) {
        final pr = i.personalRules?.trim() ?? '';
        return pr.isNotEmpty ||
            i.metadata?['has_score_template'] == true ||
            i.metadata?['modular_rules'] != null;
      }).toList();
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

    if (videogamePlatforms.isNotEmpty) {
      result = result.where((i) {
        return videogamePlatforms.any((pid) {
          final platform = VideogamePlatform.fromId(pid);
          if (platform == null) return false;
          return itemMatchesVideogamePlatform(i.metadata, platform);
        });
      }).toList();
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
      case CollectionSort.favoritesFirst:
        final fa = a.isFavorite ? 0 : 1;
        final fb = b.isFavorite ? 0 : 1;
        final cmp = fa.compareTo(fb);
        return cmp != 0
            ? cmp
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
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
      case CollectionSort.estimatedValueDesc:
        final va = marketSecondhandPriceFromMetadata(a.metadata) ??
            marketNewPriceMinFromMetadata(a.metadata) ??
            (sort == CollectionSort.estimatedValueDesc ? -1 : double.infinity);
        final vb = marketSecondhandPriceFromMetadata(b.metadata) ??
            marketNewPriceMinFromMetadata(b.metadata) ??
            (sort == CollectionSort.estimatedValueDesc ? -1 : double.infinity);
        final cmp = sort == CollectionSort.estimatedValueDesc
            ? vb.compareTo(va)
            : va.compareTo(vb);
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
      case CollectionSort.playsDesc:
        final cmp = playCountOf(b).compareTo(playCountOf(a));
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.costPerPlayAsc:
        final pa = playCountOf(a);
        final pb = playCountOf(b);
        final va = marketSecondhandPriceFromMetadata(a.metadata) ??
            marketNewPriceMinFromMetadata(a.metadata);
        final vb = marketSecondhandPriceFromMetadata(b.metadata) ??
            marketNewPriceMinFromMetadata(b.metadata);
        final ca = (pa > 0 && va != null) ? va / pa : double.infinity;
        final cb = (pb > 0 && vb != null) ? vb / pb : double.infinity;
        final cmp = ca.compareTo(cb);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.durationAsc:
        final ta = playingTimeOf(a) ?? 1 << 20;
        final tb = playingTimeOf(b) ?? 1 << 20;
        final cmp = ta.compareTo(tb);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.complexityAsc:
        final wa = complexityOf(a) ?? 99;
        final wb = complexityOf(b) ?? 99;
        final cmp = wa.compareTo(wb);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.yearDesc:
        final ya = yearOf(a) ?? 0;
        final yb = yearOf(b) ?? 0;
        final cmp = yb.compareTo(ya);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      case CollectionSort.dateAddedDesc:
        final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = db.compareTo(da);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
    }
  }
}
