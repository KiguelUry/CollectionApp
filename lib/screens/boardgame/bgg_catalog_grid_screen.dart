import 'package:flutter/material.dart';

import '../../models/bgg_catalog_game.dart';
import '../../services/boardgame_discovery_service.dart';
import '../../services/user_boardgame_collection_service.dart';
import '../../utils/boardgame_bulk_add.dart';
import '../../utils/boardgame_quick_add.dart';
import '../../utils/collection_grid_layout.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/catalog/catalog_item_tile.dart';
import '../../widgets/cover_preview_sheet.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/loading_placeholder.dart';

enum BggCatalogSource {
  popular,
  forYou,
  friends,
  genre,
  search,
}

/// Grille catalogue BGG avec ajout rapide collection / wishlist.
class BggCatalogGridScreen extends StatefulWidget {
  final BggCatalogSource source;
  final String title;
  final String? initialQuery;
  final String? genreEn;
  final String? genreLabel;

  const BggCatalogGridScreen({
    super.key,
    required this.source,
    required this.title,
    this.initialQuery,
    this.genreEn,
    this.genreLabel,
  });

  @override
  State<BggCatalogGridScreen> createState() => _BggCatalogGridScreenState();
}

class _BggCatalogGridScreenState extends State<BggCatalogGridScreen> {
  static const _accent = Colors.orange;

  final _discovery = BoardgameDiscoveryService();
  final _scrollController = ScrollController();
  late final TextEditingController _searchController;

  List<BggCatalogGame> _allGames = [];
  Set<String> _ownedKeys = {};
  Set<String> _wishlistKeys = {};
  int _visibleCount = catalogPageSize;
  bool _hideOwnedAndWishlist = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _key(BggCatalogGame g) => g.catalogKey;

  List<BggCatalogGame> get _filteredGames {
    if (!_hideOwnedAndWishlist) return _allGames;
    return _allGames.where((g) {
      final k = _key(g);
      return !_ownedKeys.contains(k) && !_wishlistKeys.contains(k);
    }).toList();
  }

  List<BggCatalogGame> get _visibleGames {
    final filtered = _filteredGames;
    if (_visibleCount >= filtered.length) return filtered;
    return filtered.take(_visibleCount).toList();
  }

  bool get _canLoadMore => _visibleCount < _filteredGames.length;

  void _onScroll() {
    if (!_canLoadMore || _loadingMore || _loading) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (!_canLoadMore) return;
    setState(() {
      _loadingMore = true;
      _visibleCount += catalogPageSize;
      _loadingMore = false;
    });
  }

  Future<List<BggCatalogGame>> _fetchGames() async {
    return switch (widget.source) {
      BggCatalogSource.popular => _discovery.fetchPopular(),
      BggCatalogSource.forYou => _discovery.fetchForYou(),
      BggCatalogSource.friends => _discovery.fetchFriendRecentAdds(),
      BggCatalogSource.genre => _discovery.fetchByGenre(
          widget.genreEn ?? '',
        ),
      BggCatalogSource.search => _discovery.search(
          _searchController.text.trim().isNotEmpty
              ? _searchController.text.trim()
              : (widget.initialQuery ?? ''),
        ),
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _visibleCount = catalogPageSize;
    });

    try {
      final gamesFuture = _fetchGames();
      final svc = UserBoardgameCollectionService();
      final ownedFuture = svc.ownedCatalogKeys();
      final wishlistFuture = svc.wishlistCatalogKeys();

      final results = await Future.wait([
        gamesFuture,
        ownedFuture,
        wishlistFuture,
      ]);

      if (!mounted) return;
      setState(() {
        _allGames = results[0] as List<BggCatalogGame>;
        _ownedKeys = results[1] as Set<String>;
        _wishlistKeys = results[2] as Set<String>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _runSearch() async {
    final q = _searchController.text.trim();
    if (q.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tape au moins 2 lettres.')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _visibleCount = catalogPageSize;
    });
    try {
      final games = await _discovery.search(q);
      if (!mounted) return;
      setState(() {
        _allGames = games;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refreshOwnedState() async {
    final svc = UserBoardgameCollectionService();
    final owned = await svc.ownedCatalogKeys();
    final wishlist = await svc.wishlistCatalogKeys();
    if (!mounted) return;
    setState(() {
      _ownedKeys = owned;
      _wishlistKeys = wishlist;
    });
  }

  Future<void> _openAddDialog(BggCatalogGame game) async {
    await quickAddBoardgameFromCatalog(context, game: game);
    await _refreshOwnedState();
  }

  Future<void> _toggleWishlist(BggCatalogGame game) async {
    final key = _key(game);
    final inWishlist = _wishlistKeys.contains(key);
    final ok = await toggleBoardgameWishlist(
      context,
      game: game,
      currentlyInWishlist: inWishlist,
    );
    if (!mounted || !ok) return;
    setState(() {
      if (inWishlist) {
        _wishlistKeys.remove(key);
      } else {
        _wishlistKeys.add(key);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          inWishlist
              ? '« ${game.title} » retiré de la wishlist'
              : '« ${game.title} » ajouté à la wishlist',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showSearch =
        widget.source == BggCatalogSource.search ||
        widget.source == BggCatalogSource.genre;
    final visible = _visibleGames;
    final filteredCount = _filteredGames.length;

    return Scaffold(
      appBar: AppAppBar(title: widget.title),
      body: Column(
        children: [
          if (showSearch || widget.source == BggCatalogSource.search)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: 'Rechercher un jeu sur BGG…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _runSearch,
                  ),
                ),
              ),
            ),
          if (widget.genreLabel != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Genre : ${widget.genreLabel}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Masquer ceux que j\'ai déjà'),
                  selected: _hideOwnedAndWishlist,
                  onSelected: (v) {
                    setState(() {
                      _hideOwnedAndWishlist = v;
                      _visibleCount = catalogPageSize;
                    });
                  },
                ),
                const Spacer(),
                if (!_loading && filteredCount > 0)
                  Text(
                    '$filteredCount jeu${filteredCount > 1 ? 'x' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingPlaceholder(grid: true, count: 9)
                : _error != null
                    ? EmptyState(
                        icon: Icons.cloud_off,
                        title: 'Chargement impossible',
                        message: _error!,
                        iconColor: _accent,
                      )
                    : visible.isEmpty
                        ? EmptyState(
                            icon: Icons.casino_outlined,
                            title: 'Aucun jeu',
                            message: _hideOwnedAndWishlist
                                ? 'Tout est déjà dans ta collection ou ta wishlist. Désactive le filtre.'
                                : widget.source == BggCatalogSource.friends
                                    ? 'Aucun ami n\'a ajouté de jeu récemment (ou collections non partagées).'
                                    : 'Essaie une autre recherche ou reviens plus tard.',
                            iconColor: _accent,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: GridView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  CollectionGridLayout.gridDelegate(
                                context,
                                mobileColumns: 3,
                                childAspectRatio: 0.62,
                                spacing: 6,
                              ),
                              itemCount:
                                  visible.length + (_canLoadMore ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i >= visible.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final game = visible[i];
                                final owned = _ownedKeys.contains(_key(game));
                                final inWishlist =
                                    _wishlistKeys.contains(_key(game));
                                return CatalogItemTile(
                                  key: ValueKey(_key(game)),
                                  name: game.title,
                                  imageUrl: game.imageUrl,
                                  subtitle: game.subtitle,
                                  accent: _accent,
                                  owned: owned,
                                  inWishlist: inWishlist,
                                  aspectRatio: 1,
                                  onTap: () => _openAddDialog(game),
                                  onLongPress: () => showCoverPreview(
                                    context,
                                    imageUrl: game.imageUrl,
                                    title: game.title,
                                    boxedCover: true,
                                  ),
                                  onQuickAdd: () async {
                                    if (owned) {
                                      final ok = await silentRemoveBoardgame(
                                        game: game,
                                      );
                                      if (!mounted || !ok) return;
                                      setState(() {
                                        _ownedKeys.remove(_key(game));
                                      });
                                      return;
                                    }
                                    final ok = await silentAddBoardgame(
                                      context,
                                      game: game,
                                    );
                                    if (!mounted || !ok) return;
                                    setState(() {
                                      _ownedKeys.add(_key(game));
                                      _wishlistKeys.remove(_key(game));
                                    });
                                  },
                                  onQuickWishlist: () => _toggleWishlist(game),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
