import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../services/friend_videogame_feed_service.dart';
import '../services/rawg_service.dart';
import '../services/videogame_catalog_service.dart';
import '../utils/collection_grid_layout.dart';
import '../utils/videogame_quick_add.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/catalog/catalog_item_tile.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/loading_placeholder.dart';

enum VideogameCatalogSource { popular, friends, search }

/// Grille découverte jeux vidéo (populaires / amis / recherche).
class VideogameCatalogGridScreen extends StatefulWidget {
  final VideogameCatalogSource source;
  final String title;
  final String? initialQuery;

  const VideogameCatalogGridScreen({
    super.key,
    required this.source,
    required this.title,
    this.initialQuery,
  });

  @override
  State<VideogameCatalogGridScreen> createState() =>
      _VideogameCatalogGridScreenState();
}

class _VideogameCatalogGridScreenState
    extends State<VideogameCatalogGridScreen> {
  static final _accent = Colors.green.shade700;

  late final TextEditingController _searchController;
  List<_VgCatalogRow> _rows = [];
  Set<String> _ownedKeys = {};
  bool _loading = true;
  String? _error;

  bool get _searchAwaitingQuery =>
      widget.source == VideogameCatalogSource.search &&
      _searchController.text.trim().isEmpty &&
      (widget.initialQuery == null || widget.initialQuery!.trim().isEmpty);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    if (_searchAwaitingQuery) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOwned() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final rows = await Supabase.instance.client
        .from('collection_items')
        .select('title, metadata')
        .eq('category', CollectionCategory.videogame.dbValue)
        .or('added_by.eq.$userId,location_user_id.eq.$userId')
        .eq('is_wishlist', false);
    final keys = <String>{};
    for (final r in rows as List) {
      final map = Map<String, dynamic>.from(r as Map);
      final rawg = (map['metadata'] as Map?)?['rawg_id']?.toString();
      if (rawg != null && rawg.isNotEmpty) {
        keys.add('id:$rawg');
      }
      final title = map['title']?.toString().trim().toLowerCase();
      if (title != null && title.isNotEmpty) keys.add('t:$title');
    }
    if (mounted) setState(() => _ownedKeys = keys);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadOwned();
      final rows = switch (widget.source) {
        VideogameCatalogSource.popular => await _loadPopular(),
        VideogameCatalogSource.friends => await _loadFriends(),
        VideogameCatalogSource.search => await _loadSearch(),
      };
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<List<_VgCatalogRow>> _loadPopular() async {
    final games = await RawgService.popular();
    return games
        .map(
          (g) => _VgCatalogRow(
            hit: g,
            subtitle: [
              if (g['year']?.isNotEmpty == true) g['year'],
              if (g['rawg_rating']?.isNotEmpty == true)
                '★ ${g['rawg_rating']}',
            ].whereType<String>().join(' · '),
          ),
        )
        .toList();
  }

  Future<List<_VgCatalogRow>> _loadFriends() async {
    final feed = await FriendVideogameFeedService().fetchRecentFriendAdds();
    return feed
        .map(
          (f) => _VgCatalogRow(
            hit: f.toCatalogHit(),
            subtitle: 'Ajouté par ${f.friendUsername}',
          ),
        )
        .toList();
  }

  Future<List<_VgCatalogRow>> _loadSearch() async {
    final q = _searchController.text.trim();
    if (q.length < 2) return [];
    final games = await VideogameCatalogService.search(q);
    return games
        .map(
          (g) => _VgCatalogRow(
            hit: g,
            subtitle: [
              if (g['year']?.isNotEmpty == true) g['year'],
              if (g['platform']?.isNotEmpty == true) g['platform'],
            ].whereType<String>().join(' · '),
          ),
        )
        .toList();
  }

  bool _isOwned(_VgCatalogRow row) {
    final id = row.hit['rawg_id'];
    if (id != null && id.isNotEmpty && _ownedKeys.contains('id:$id')) {
      return true;
    }
    final t = row.hit['title']?.trim().toLowerCase();
    return t != null && t.isNotEmpty && _ownedKeys.contains('t:$t');
  }

  Future<void> _add(_VgCatalogRow row) async {
    final ok = await quickAddVideogameFromHit(context, row.hit);
    if (ok && mounted) _loadOwned();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: widget.title,
        showBackButton: true,
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.source == VideogameCatalogSource.search)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: 'Nom du jeu',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _load,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const LoadingPlaceholder()
                : _error != null
                    ? EmptyState(
                        icon: Icons.error_outline,
                        title: 'Erreur',
                        message: _error!,
                      )
                    : _searchAwaitingQuery
                        ? const EmptyState(
                            icon: Icons.search,
                            title: 'Rechercher',
                            message: 'Tape au moins 2 lettres.',
                          )
                        : _rows.isEmpty
                            ? EmptyState(
                                icon: Icons.sports_esports_outlined,
                                title: 'Rien à afficher',
                                message: widget.source ==
                                        VideogameCatalogSource.friends
                                    ? 'Tes amis n’ont pas encore ajouté de jeux vidéo.'
                                    : 'Aucun résultat.',
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    CollectionGridLayout.gridDelegate(
                                  context,
                                  mobileColumns: 2,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: _rows.length,
                                itemBuilder: (context, i) {
                                  final row = _rows[i];
                                  final owned = _isOwned(row);
                                  return CatalogItemTile(
                                    name: row.hit['title'] ?? '',
                                    imageUrl: row.hit['image_url'],
                                    subtitle: row.subtitle,
                                    accent: _accent,
                                    owned: owned,
                                    aspectRatio: 3 / 4,
                                    placeholderIcon: Icons.sports_esports,
                                    onTap: owned ? () {} : () => _add(row),
                                    onQuickAdd:
                                        owned ? null : () => _add(row),
                                  );
                                },
                              ),
          ),
        ],
      ),
    );
  }
}

class _VgCatalogRow {
  final Map<String, String> hit;
  final String? subtitle;

  const _VgCatalogRow({required this.hit, this.subtitle});
}
