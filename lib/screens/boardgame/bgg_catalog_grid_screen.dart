import 'package:flutter/material.dart';

import '../../models/bgg_catalog_game.dart';
import '../../services/boardgame_discovery_service.dart';
import '../../services/user_boardgame_collection_service.dart';
import '../../utils/boardgame_bulk_add.dart';
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
  late final TextEditingController _searchController;

  List<BggCatalogGame> _games = [];
  Set<String> _ownedKeys = {};
  Set<String> _wishlistKeys = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _key(BggCatalogGame g) => g.catalogKey;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final games = await switch (widget.source) {
        BggCatalogSource.popular => _discovery.fetchPopular(),
        BggCatalogSource.forYou => _discovery.fetchForYou(),
        BggCatalogSource.friends => _discovery.fetchFriendsLove(),
        BggCatalogSource.genre => _discovery.fetchByGenre(
            widget.genreEn ?? '',
          ),
        BggCatalogSource.search => _discovery.search(
            _searchController.text.trim().isNotEmpty
                ? _searchController.text.trim()
                : (widget.initialQuery ?? ''),
          ),
      };

      final svc = UserBoardgameCollectionService();
      final owned = await svc.ownedCatalogKeys();
      final wishlist = await svc.wishlistCatalogKeys();

      if (!mounted) return;
      setState(() {
        _games = games;
        _ownedKeys = owned;
        _wishlistKeys = wishlist;
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
    setState(() => _loading = true);
    final games = await _discovery.search(q);
    if (!mounted) return;
    setState(() {
      _games = games;
      _loading = false;
    });
  }

  Future<void> _quickAdd(BggCatalogGame game) async {
    final ok = await silentAddBoardgame(context, game: game);
    if (!mounted || !ok) return;
    setState(() {
      _ownedKeys.add(_key(game));
      _wishlistKeys.remove(_key(game));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('« ${game.title} » ajouté à ta collection'),
      ),
    );
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
                    : _games.isEmpty
                        ? EmptyState(
                            icon: Icons.casino_outlined,
                            title: 'Aucun jeu',
                            message: widget.source == BggCatalogSource.friends
                                ? 'Ajoute des amis ou leurs collections ne sont pas partagées.'
                                : 'Essaie une autre recherche ou reviens plus tard.',
                            iconColor: _accent,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  CollectionGridLayout.gridDelegate(
                                context,
                                mobileColumns: 3,
                                childAspectRatio: 0.62,
                                spacing: 6,
                              ),
                              itemCount: _games.length,
                              itemBuilder: (context, i) {
                                final game = _games[i];
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
                                  onTap: () => _quickAdd(game),
                                  onLongPress: () => showCoverPreview(
                                    context,
                                    imageUrl: game.imageUrl,
                                    title: game.title,
                                  ),
                                  onQuickAdd:
                                      owned ? null : () => _quickAdd(game),
                                  onQuickWishlist: owned
                                      ? null
                                      : () => _toggleWishlist(game),
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
