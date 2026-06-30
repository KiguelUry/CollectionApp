import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_subcategory.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../models/card_subcategory.dart';
import '../models/category_metadata.dart';
import '../models/media_format_ui.dart';
import '../services/bgg_service.dart';
import '../services/book_catalog_service.dart';
import '../services/card_catalog_service.dart';
import '../services/media_catalog_service.dart';
import '../services/profile_service.dart';
import '../utils/boardgame_expansion_flow.dart';
import '../utils/boardgame_expansion_reconcile.dart';
import '../utils/boardgame_collection_visibility.dart';
import '../utils/boardgame_display.dart';
import '../utils/collection_item_filters.dart';
import '../utils/owned_quantity_index.dart';
import '../utils/debounced_runner.dart';
import '../utils/holder_filter.dart';
import '../utils/supabase_embeds.dart';
import '../utils/whereabouts_persistence.dart';
import '../utils/wishlist_promote.dart';
import '../services/global_play_history_service.dart';
import '../models/collection_view_mode.dart';
import '../models/item_tag.dart';
import '../models/storage_location.dart';
import '../services/item_group_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/collection_refresh.dart';
import '../services/tag_service.dart';
import '../widgets/category_collection_tab_pane.dart';
import '../widgets/category_collection_header.dart';
import '../widgets/category_collection_shell.dart';
import '../widgets/isbn_scan_sheet.dart';
import 'global_play_history_screen.dart';
import 'shake_pick_screen.dart';
import '../widgets/add_item_manual_dialog.dart';
import '../widgets/add_item_options_dialog.dart';
import '../widgets/bgg_search_dialog.dart';
import '../widgets/book_search_dialog.dart' show showBookSearch;
import '../widgets/card_search_dialog.dart' show showCardSearch;
import '../widgets/media_search_dialog.dart' show showMediaSearch;
import '../widgets/ui/add_option_tile.dart';
import '../models/lego_build_kind.dart';
import '../models/tech_subcategory.dart';
import '../services/lego_catalog_service.dart';
import '../services/movie_catalog_service.dart';
import '../services/videogame_catalog_service.dart';
import '../widgets/watch_quick_search_sheet.dart';
import '../utils/catalog_hit_metadata.dart';
import '../widgets/book_subcategory_picker.dart';
import '../widgets/catalog_search_sheet.dart';
import 'book/book_collection_screen.dart';
import 'book_wishlist_tab.dart';

class HomeScreen extends StatefulWidget {
  final CollectionCategory category;
  final String? screenTitle;
  final CardSubcategory? fixedCardSubcategory;
  final MediaFormat? fixedMediaFormat;

  final Color? accentOverride;
  final String? customTypeId;
  final String? customTypeName;
  final LegoBuildKind? fixedLegoKind;
  final TechSubcategory? fixedTechSubcategory;
  final Map<String, String>? pendingCatalogHit;
  /// Wishlist seule (évite la liste plate collection livres).
  final bool bookWishlistOnly;

  const HomeScreen({
    super.key,
    required this.category,
    this.screenTitle,
    this.fixedCardSubcategory,
    this.fixedMediaFormat,
    this.accentOverride,
    this.customTypeId,
    this.customTypeName,
    this.fixedLegoKind,
    this.fixedTechSubcategory,
    this.pendingCatalogHit,
    this.bookWishlistOnly = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _tagService = TagService();
  late final TabController _tabController;

  late final String _userId;
  late final Stream<List<Map<String, dynamic>>> _itemsStream;
  StreamSubscription<List<Map<String, dynamic>>>? _itemsSub;
  List<Map<String, dynamic>> _itemRows = [];
  bool _itemsLoading = true;
  int _enrichGeneration = 0;
  List<CollectionItem>? _enrichedItems;
  bool _expansionReconcileDone = false;
  CollectionViewMode _viewMode = CollectionViewMode.grid;
  bool _mediaGroupByArtist = false;
  List<StorageLocation> _locations = [];
  List<ItemTag> _tags = [];
  List<CollectionGroup> _groups = [];
  Map<String, String> _groupNamesById = {};
  Set<String> _myGroupIds = {};
  bool _bggRatingEnrichInFlight = false;
  final _reloadDebounce = DebouncedRunner();
  static const _reloadDebounceDelay = Duration(milliseconds: 300);

  void _scheduleReloadItemsFromDb() {
    _reloadDebounce.run(
      delay: _reloadDebounceDelay,
      action: () {
        if (!mounted) return;
        unawaited(_reloadItemsFromDb());
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _userId = Supabase.instance.client.auth.currentUser!.id;
    final rawStream = Supabase.instance.client
        .from('collection_items')
        .stream(primaryKey: ['id'])
        .eq('category', widget.category.dbValue);
    _itemsStream = rawStream.map(_filterAndScopeRows);
    _itemsSub = _itemsStream.listen((_) => _scheduleReloadItemsFromDb());
    CollectionRefresh.instance.addListener(_scheduleReloadItemsFromDb);
    _reloadItemsFromDb();
    _loadFilterData();
    if (widget.pendingCatalogHit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openFromCatalogHit(widget.pendingCatalogHit!);
      });
    }
    if (widget.category == CollectionCategory.boardgame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeReconcileExpansions();
      });
    }
  }

  Future<void> _maybeReconcileExpansions() async {
    if (_expansionReconcileDone || !mounted) return;
    _expansionReconcileDone = true;
    final result = await repairAndReconcileBoardgameExpansions();
    if (!mounted || !result.changed) return;
    final parts = <String>[];
    if (result.metadataFixedCount > 0) {
      parts.add(
        '${result.metadataFixedCount} fiche${result.metadataFixedCount > 1 ? 's' : ''} BGG corrigée${result.metadataFixedCount > 1 ? 's' : ''}',
      );
    }
    if (result.repairedCount > 0) {
      parts.add(
        '${result.repairedCount} lien${result.repairedCount > 1 ? 's' : ''} réparé${result.repairedCount > 1 ? 's' : ''}',
      );
    }
    if (result.mergedCount > 0) {
      parts.add(
        '${result.mergedCount} extension${result.mergedCount > 1 ? 's' : ''} rattachée${result.mergedCount > 1 ? 's' : ''}',
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parts.join(' · '))),
    );
  }

  List<Map<String, dynamic>> _filterAndScopeRows(
    List<Map<String, dynamic>> rows,
  ) {
    var filtered = _scopeRows(rows);

    if (widget.customTypeId != null) {
      filtered = filtered
          .where((r) => r['subcategory'] == widget.customTypeId)
          .toList();
    }

    if (widget.fixedLegoKind != null) {
      filtered = filtered.where((r) {
        final meta = CategoryMetadata.parse(r['metadata']);
        final kind = meta?['lego_kind']?.toString() ?? 'lego';
        return kind == widget.fixedLegoKind!.dbValue;
      }).toList();
    }

    return filtered;
  }

  Color get _accentColor =>
      widget.accentOverride ?? widget.category.color;

  void _openFromCatalogHit(Map<String, String> hit) {
    var meta = metadataFromCatalogHit(hit, widget.category);
    if (widget.fixedLegoKind != null) {
      meta = {...meta, 'lego_kind': widget.fixedLegoKind!.dbValue};
    }
    _showOptionsDialog(
      title: hit['title'] ?? 'Objet',
      imageUrl: hit['image_url']?.isNotEmpty == true ? hit['image_url'] : null,
      metadata: meta,
    );
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    _reloadDebounce.dispose();
    CollectionRefresh.instance.removeListener(_scheduleReloadItemsFromDb);
    _tabController.dispose();
    super.dispose();
  }

  void _onItemRows(List<Map<String, dynamic>> rows) {
    if (!mounted) return;
    setState(() {
      _itemRows = rows;
      _itemsLoading = false;
    });
    _scheduleEnrich();
  }

  Future<void> _reloadItemsFromDb() async {
    try {
      var query = Supabase.instance.client
          .from('collection_items')
          .select(SupabaseEmbeds.collectionItemList)
          .eq('category', widget.category.dbValue);
      final data = await query;
      if (!mounted) return;
      _onItemRows(_filterAndScopeRows(List<Map<String, dynamic>>.from(data)));
    } catch (_) {
      if (mounted) setState(() => _itemsLoading = false);
    }
  }

  void _scheduleEnrich() {
    final gen = ++_enrichGeneration;
    final parsed = _parseItems(_itemRows);
    _tagService.enrichItems(parsed).then((items) {
      if (!mounted || gen != _enrichGeneration) return;
      setState(() => _enrichedItems = items);
    });
  }

  List<CollectionItem> _visibleCollectionItems(List<CollectionItem> scoped) {
    if (widget.category != CollectionCategory.boardgame) return scoped;
    return scoped
        .where((item) => !isBoardgameHiddenInGlobalCollection(item, scoped))
        .toList();
  }

  bool get _addingToWishlist => _tabController.index == 1;

  List<CollectionItem> _parseItems(List<Map<String, dynamic>> rows) {
    return rows.map((json) {
      final item = CollectionItem.fromJson(json);
      final gid = item.groupId;
      if (gid == null) return item;
      final name = _groupNamesById[gid] ?? item.groupName;
      if (name == null || name == item.groupName) return item;
      return item.copyWith(groupName: name);
    }).toList();
  }

  Future<void> _enrichBggRatingsForSort(List<CollectionItem> items) async {
    if (widget.category != CollectionCategory.boardgame) return;
    if (_bggRatingEnrichInFlight) return;

    final missing = items
        .where(
          (i) =>
              parseBggAvgRating(i.metadata?['bgg_avg_rating']) == null &&
              (i.metadata?['bgg_id']?.toString().isNotEmpty ?? false),
        )
        .take(20)
        .toList();
    if (missing.isEmpty) return;

    _bggRatingEnrichInFlight = true;
    try {
      var changed = false;
      for (final item in missing) {
        final bggId = item.metadata!['bgg_id'].toString();
        final details = await BggService.getGameFullDetails(bggId);
        if (details == null) continue;

        final meta = Map<String, dynamic>.from(item.metadata ?? {});
        var itemDirty = false;
        for (final key in [
          'bgg_avg_rating',
          'bgg_short_description',
          'bgg_best_players',
        ]) {
          final v = details[key];
          if (v == null || meta[key] == v) continue;
          meta[key] = v;
          itemDirty = true;
        }
        if (!itemDirty) continue;

        await Supabase.instance.client
            .from('collection_items')
            .update({'metadata': meta})
            .eq('id', item.id);
        changed = true;
      }
      if (changed && mounted) _scheduleReloadItemsFromDb();
    } finally {
      _bggRatingEnrichInFlight = false;
    }
  }

  Future<void> _loadFilterData() async {
    try {
      final results = await Future.wait([
        LocationService().fetchLocations(),
        _tagService.fetchMyTags(),
        GroupService().fetchMyGroups(),
      ]);
      if (mounted) {
        final groups = results[2] as List<CollectionGroup>;
        setState(() {
          _locations = results[0] as List<StorageLocation>;
          _tags = results[1] as List<ItemTag>;
          _groups = groups;
          _groupNamesById = {for (final g in groups) g.id: g.name};
          _myGroupIds = groups.map((g) => g.id).toSet();
        });
        _scheduleReloadItemsFromDb();
      }
    } catch (_) {}
  }

  Future<void> _scanIsbnAndAdd() async {
    final isbn = await showIsbnScanSheet(context);
    if (isbn == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Flexible(child: Text('Recherche du livre…')),
            ],
          ),
        ),
      ),
    );

    final book = await BookCatalogService.lookupByIsbn(isbn);

    if (!mounted) return;
    Navigator.pop(context);

    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Livre introuvable pour cet ISBN (essaie la recherche manuelle)',
          ),
        ),
      );
      return;
    }

    final suggested = book['subcategory_hint'] != null
        ? BookSubcategory.fromDbValue(book['subcategory_hint'])
        : BookSubcategory.other;

    final subcategory = await showBookSubcategoryPicker(
      context,
      suggested: suggested,
    );
    if (!mounted || subcategory == null) return;

    _showOptionsDialog(
      title: book['title']!,
      imageUrl: book['image_url']?.isNotEmpty == true ? book['image_url'] : null,
      subcategory: subcategory.dbValue,
      metadata: BookCatalogService.metadataFromLookup(book),
    );
  }

  List<Map<String, dynamic>> _scopeRows(List<Map<String, dynamic>> rows) {
    return rows.where((row) {
      final addedBy = row['added_by'] as String?;
      final locUser = row['location_user_id'] as String?;
      if (addedBy == _userId || locUser == _userId) return true;
      final gid = row['group_id'] as String?;
      return gid != null && _myGroupIds.contains(gid);
    }).toList();
  }

  Future<void> _confirmDeleteItem(CollectionItem item) async {
    final isGroup = item.isGroupOwned;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isGroup ? 'Retirer ?' : 'Supprimer ?'),
        content: Text(
          isGroup
              ? '« ${item.title} » sera retiré de « ${item.groupName ?? 'ce groupe'} ».'
              : '« ${item.title} » sera retiré de ta collection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(isGroup ? 'Retirer' : 'Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    if (item.category == CollectionCategory.boardgame) {
      await GlobalPlayHistoryService().archivePlaysFromDeletedItem(item);
    }

    await Supabase.instance.client
        .from('collection_items')
        .delete()
        .eq('id', item.id);
    CollectionRefresh.instance.bump();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isGroup ? '« ${item.title} » retiré du groupe' : '« ${item.title} » supprimé',
        ),
      ),
    );
  }

  Future<void> _confirmBulkDeleteItems(List<CollectionItem> items) async {
    for (final item in items) {
      if (item.category == CollectionCategory.boardgame) {
        await GlobalPlayHistoryService().archivePlaysFromDeletedItem(item);
      }
      await Supabase.instance.client
          .from('collection_items')
          .delete()
          .eq('id', item.id);
    }
    CollectionRefresh.instance.bump();
    if (!mounted) return;
    final count = items.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$count objet${count > 1 ? 's' : ''} supprimé${count > 1 ? 's' : ''}',
        ),
      ),
    );
  }

  void _onAddPressed() {
    if (widget.category.supportsBggSearch) {
      _showBoardgameAddChooser();
    } else if (widget.category.supportsOpenLibrarySearch) {
      _showBookSearchDialog();
    } else if (widget.category == CollectionCategory.card) {
      _showCardAddChooser();
    } else if (widget.category == CollectionCategory.media) {
      _showMediaAddChooser();
    } else if (widget.category == CollectionCategory.movie) {
      _showMovieAddChooser();
    } else if (widget.category == CollectionCategory.videogame) {
      _showVideogameAddChooser();
    } else if (widget.category == CollectionCategory.lego) {
      _showLegoAddChooser();
    } else if (widget.category == CollectionCategory.watch) {
      _showWatchAddChooser();
    } else {
      _showManualAddFlow();
    }
  }

  void _showCardAddChooser() {
    final sub =
        widget.fixedCardSubcategory ?? CardSubcategory.other;
    final canSearch = CardCatalogService.supportsSearch(sub);

    if (!canSearch) {
      _showManualAddFlow(
        cardSubcategory: sub,
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ajouter — ${sub.label}',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              AddOptionTile(
                icon: Icons.search_rounded,
                color: sub.color,
                title: 'Chercher dans le catalogue',
                subtitle: CardCatalogService.catalogLabel(sub),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCardSearchDialog(sub);
                },
              ),
              const SizedBox(height: 8),
              AddOptionTile(
                icon: Icons.edit_outlined,
                color: sub.color,
                title: 'Saisir à la main',
                subtitle: 'Titre, état, photo…',
                onTap: () {
                  Navigator.pop(ctx);
                  _showManualAddFlow(cardSubcategory: sub);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCardSearchDialog(CardSubcategory sub) {
    showCardSearch(
      context,
      subcategory: sub,
      onManualEntry: () => _showManualAddFlow(cardSubcategory: sub),
    ).then((card) {
      if (card == null || !mounted) return;
      _showOptionsDialog(
        title: card['title']!,
        imageUrl: card['image_url']?.isNotEmpty == true ? card['image_url'] : null,
        subcategory: sub.dbValue,
        metadata: CardCatalogService.metadataFromResult(card, sub),
      );
    });
  }

  void _showMediaAddChooser() {
    final format = widget.fixedMediaFormat ?? MediaFormat.vinyl;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ajouter — ${format.label}',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              AddOptionTile(
                icon: Icons.search_rounded,
                color: format.color,
                title: 'Rechercher / scanner',
                subtitle: MediaCatalogService.catalogLabel(format: format),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMediaSearchDialog(format);
                },
              ),
              const SizedBox(height: 8),
              AddOptionTile(
                icon: Icons.edit_outlined,
                color: format.color,
                title: 'Saisir à la main',
                subtitle: 'Titre, artiste, photo…',
                onTap: () {
                  Navigator.pop(ctx);
                  _showManualAddFlow(mediaFormat: format);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMediaSearchDialog(MediaFormat format) {
    showMediaSearch(
      context,
      format: format,
      onManualEntry: () => _showManualAddFlow(mediaFormat: format),
    ).then((album) {
      if (album == null || !mounted) return;
      final meta = MediaCatalogService.metadataFromLookup(album, format);
      _showOptionsDialog(
        title: album['title']!,
        imageUrl: album['image_url']?.isNotEmpty == true ? album['image_url'] : null,
        metadata: meta,
      );
    });
  }

  void _showCatalogAddChooser({
    required String label,
    required Color color,
    required VoidCallback onSearch,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ajouter — $label',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              AddOptionTile(
                icon: Icons.search_rounded,
                color: color,
                title: 'Chercher dans le catalogue',
                subtitle: 'Recherche en ligne si clé API',
                onTap: () {
                  Navigator.pop(ctx);
                  onSearch();
                },
              ),
              const SizedBox(height: 8),
              AddOptionTile(
                icon: Icons.edit_outlined,
                color: color,
                title: 'Saisir à la main',
                subtitle: 'Titre, détails, photo…',
                onTap: () {
                  Navigator.pop(ctx);
                  _showManualAddFlow();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMovieAddChooser() {
    _showCatalogAddChooser(
      label: widget.screenTitle ?? 'Films',
      color: _accentColor,
      onSearch: () {
        showCatalogSearchSheet(
          context,
          title: 'Rechercher un film (Blu-ray, DVD…)',
          hint: 'Titre du film',
          apiHint: MovieCatalogService.catalogLabel,
          search: MovieCatalogService.search,
          accent: _accentColor,
          onManualEntry: _showManualAddFlow,
        ).then((hit) {
          if (hit != null && mounted) _openFromCatalogHit(hit);
        });
      },
    );
  }

  void _showVideogameAddChooser() {
    _showCatalogAddChooser(
      label: widget.screenTitle ?? 'Jeux vidéo',
      color: _accentColor,
      onSearch: () {
        showCatalogSearchSheet(
          context,
          title: 'Rechercher un jeu',
          hint: 'Nom du jeu',
          apiHint: VideogameCatalogService.catalogLabel,
          search: VideogameCatalogService.search,
          accent: _accentColor,
          onManualEntry: _showManualAddFlow,
        ).then((hit) {
          if (hit != null && mounted) _openFromCatalogHit(hit);
        });
      },
    );
  }

  void _showLegoAddChooser() {
    _showCatalogAddChooser(
      label: widget.screenTitle ?? 'Lego',
      color: _accentColor,
      onSearch: () {
        showCatalogSearchSheet(
          context,
          title: 'Rechercher un set Lego',
          hint: 'Nom ou n° de set (ex: 75192)',
          apiHint: LegoCatalogService.catalogLabel,
          search: LegoCatalogService.search,
          accent: _accentColor,
          onManualEntry: () => _showManualAddFlow(
            legoKind: widget.fixedLegoKind,
          ),
        ).then((hit) {
          if (hit != null && mounted) _openFromCatalogHit(hit);
        });
      },
    );
  }

  void _showWatchAddChooser() {
    _showCatalogAddChooser(
      label: widget.screenTitle ?? 'Montres',
      color: _accentColor,
      onSearch: () {
        showWatchQuickSearchSheet(
          context,
          accent: _accentColor,
          onManualEntry: _showManualAddFlow,
        ).then((hit) {
          if (hit != null && mounted) _openFromCatalogHit(hit);
        });
      },
    );
  }

  void _showBoardgameAddChooser() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Chercher sur BGG'),
              subtitle: const Text('Recherche complète via BoardGameGeek'),
              onTap: () {
                Navigator.pop(ctx);
                _showBggSearchDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Saisir le nom à la main'),
              subtitle: const Text('Sans recherche BGG'),
              onTap: () {
                Navigator.pop(ctx);
                _showManualAddFlow();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBggSearchDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => BggSearchDialog(
        onGameSelected: (bggGame) {
          Navigator.pop(dialogContext);
          _prepareBggAdd(bggGame);
        },
        onManualAdd: kIsWeb
            ? () {
                Navigator.pop(dialogContext);
                _showManualAddFlow();
              }
            : null,
      ),
    );
  }

  Future<void> _prepareBggAdd(Map<String, String> bggGame) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Flexible(child: Text('Chargement des infos BGG…')),
            ],
          ),
        ),
      ),
    );

    final bggId = bggGame['id']!;
    final details = await BggService.getGameFullDetails(bggId);

    if (!mounted) return;
    Navigator.pop(context);

    _showOptionsDialog(
      title: bggGame['title']!,
      bggId: bggId,
      imageUrl: (details?['image_url'] as String?) ?? bggGame['image_url'],
      bggDetails: details,
    );
  }

  void _showBookSearchDialog() {
    showBookSearch(
      context,
      onManualEntry: _showManualAddFlow,
      onBookSelected: (book, subcategory) => _showOptionsDialog(
        title: book['title']!,
        imageUrl: book['image_url']!.isEmpty ? null : book['image_url'],
        subcategory: subcategory.dbValue,
        metadata: BookCatalogService.metadataFromLookup(book),
        closesTwoDialogs: true,
      ),
    );
  }

  List<CollectionItem> _filterHubScope(List<CollectionItem> items) {
    final cardSub = widget.fixedCardSubcategory;
    if (cardSub != null) {
      return items.where((i) => i.subcategory == cardSub.dbValue).toList();
    }
    final mediaFmt = widget.fixedMediaFormat;
    if (mediaFmt != null) {
      return items
          .where((i) => i.metadata?['format']?.toString() == mediaFmt.dbValue)
          .toList();
    }
    final legoKind = widget.fixedLegoKind;
    if (legoKind != null) {
      return items.where((i) {
        final k = i.metadata?['lego_kind']?.toString() ?? 'lego';
        return k == legoKind.dbValue;
      }).toList();
    }
    final techSub = widget.fixedTechSubcategory;
    if (techSub != null) {
      return items
          .where((i) => i.subcategory == techSub.dbValue)
          .toList();
    }
    return items;
  }

  Future<void> _showManualAddFlow({
    CardSubcategory? cardSubcategory,
    MediaFormat? mediaFormat,
    LegoBuildKind? legoKind,
    TechSubcategory? techSubcategory,
  }) async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddItemManualDialog(
        categoryLabel: widget.screenTitle ?? widget.category.label,
        category: widget.category,
        initialCardSubcategory:
            cardSubcategory ?? widget.fixedCardSubcategory,
        initialMediaFormat: mediaFormat ?? widget.fixedMediaFormat,
        initialLegoKind: legoKind ?? widget.fixedLegoKind,
        initialTechSubcategory: techSubcategory ?? widget.fixedTechSubcategory,
        lockSubcategory: widget.fixedCardSubcategory != null ||
            widget.fixedMediaFormat != null ||
            widget.fixedLegoKind != null ||
            widget.fixedTechSubcategory != null,
      ),
    );
    if (draft == null || !mounted) return;

    _showOptionsDialog(
      title: draft['title'] as String,
      imageUrl: draft['image_url'] as String?,
      subcategory: draft['subcategory'] as String?,
      metadata: draft['metadata'] as Map<String, dynamic>?,
    );
  }

  void _showOptionsDialog({
    required String title,
    String? imageUrl,
    String? subcategory,
    Map<String, dynamic>? metadata,
    String? bggId,
    Map<String, dynamic>? bggDetails,
    bool closesTwoDialogs = false,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AddItemOptionsDialog(
        itemTitle: title,
        itemImageUrl: imageUrl,
        defaultWishlist: _addingToWishlist,
        onConfirm: (options) async {
          await _handleSave(
            dialogContext: dialogContext,
            title: title,
            options: options,
            imageUrl: imageUrl,
            subcategory: subcategory,
            metadata: metadata,
            bggId: bggId,
            bggDetails: bggDetails,
            closesTwoDialogs: closesTwoDialogs,
          );
        },
      ),
    );
  }

  Future<void> _insertCollectionItem({
    required CollectionItem item,
    required String userId,
    required AddItemOptions options,
  }) async {
    final client = Supabase.instance.client;
    final payload = buildCollectionItemInsertPayload(
      item: item,
      addedBy: userId,
      isWishlist: options.isWishlist,
      holderLabel: options.holderLabel,
      defaultUserId: userId,
    );
    final inserted = await client
        .from('collection_items')
        .insert(payload)
        .select()
        .single();
    final groupId = options.groupId;
    if (groupId != null && groupId.isNotEmpty && !options.isWishlist) {
      final saved = CollectionItem.fromJson(
        Map<String, dynamic>.from(inserted as Map),
      ).copyWith(
        metadata: Map<String, dynamic>.from(
          payload['metadata'] as Map? ?? {},
        ),
        locationUserId: payload['location_user_id'] as String?,
        groupId: groupId,
      );
      await ItemGroupService().syncItemGroupsWithItem(saved, [groupId]);
    }
  }

  Future<void> _handleSave({
    required BuildContext dialogContext,
    required String title,
    required AddItemOptions options,
    String? imageUrl,
    String? subcategory,
    Map<String, dynamic>? metadata,
    String? bggId,
    Map<String, dynamic>? bggDetails,
    bool closesTwoDialogs = false,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    String? resolvedImageUrl = imageUrl;
    int? resolvedMin;
    int? resolvedMax;
    int? resolvedTime;

    try {
      await ProfileService().ensureCurrentUserProfile();

      if (bggDetails != null) {
        resolvedImageUrl =
            (bggDetails['image_url'] as String?) ?? resolvedImageUrl;
        resolvedMin = bggDetails['min_players'] as int?;
        resolvedMax = bggDetails['max_players'] as int?;
        resolvedTime = _positivePlayingTime(bggDetails['playing_time']);
      } else if (bggId != null) {
        final details = await BggService.getGameFullDetails(bggId);
        resolvedImageUrl =
            (details?['image_url'] as String?) ?? resolvedImageUrl;
        resolvedMin = details?['min_players'] as int?;
        resolvedMax = details?['max_players'] as int?;
        resolvedTime = _positivePlayingTime(details?['playing_time']);
      }

      final resolvedSub = widget.customTypeId ?? subcategory;
      final existing = await findDuplicateRow(
        title: title,
        categoryDb: widget.category.dbValue,
        isWishlist: options.isWishlist,
        subcategory: resolvedSub,
        groupId: options.groupId,
      );
      if (!mounted) return;
      var message = '« $title » ajouté';
      if (existing != null) {
        final baseQty = options.isWishlist
            ? ((existing['quantity'] as int?) ?? 0)
            : ((existing['quantity'] as int?) ?? 1);
        final newQty = baseQty + options.quantity;
        await client
            .from('collection_items')
            .update({'quantity': newQty})
            .eq('id', existing['id']);
        message = 'Quantité mise à jour ($newQty)';
        CollectionRefresh.instance.bump();
      } else {
        final meta = Map<String, dynamic>.from(metadata ?? {});
        if (bggId != null) meta['bgg_id'] = bggId;
        if (bggDetails != null) {
          for (final key in [
            'year_published',
            'min_age',
            'bgg_categories',
            'bgg_is_expansion',
            'base_game_bgg_id',
            'base_game_title',
            'bgg_short_description',
            'bgg_avg_rating',
            'bgg_best_players',
          ]) {
            final v = bggDetails[key];
            if (v != null) meta[key] = v;
          }
        }
        if (widget.fixedLegoKind != null && !meta.containsKey('lego_kind')) {
          meta['lego_kind'] = widget.fixedLegoKind!.dbValue;
        }
        if (widget.fixedTechSubcategory != null && subcategory == null) {
          subcategory = widget.fixedTechSubcategory!.dbValue;
        }
        if (widget.customTypeName != null) {
          meta['custom_type_name'] = widget.customTypeName;
        }

        if (widget.category == CollectionCategory.boardgame &&
            bggId != null &&
            !options.isWishlist) {
          if (!mounted) return;
          final expansionMsg = await insertBoardgameWithExpansionRules(
            context: context,
            title: title,
            bggId: bggId,
            bggDetails: bggDetails,
            imageUrl: resolvedImageUrl,
            isWishlist: false,
            quantity: options.quantity,
            locationId: options.locationId,
            groupId: options.groupId,
            locationUserId: options.locationUserId,
            minPlayers: resolvedMin,
            maxPlayers: resolvedMax,
            playingTime: resolvedTime,
          );
          if (expansionMsg != null) {
            message = expansionMsg;
          } else {
            final item = CollectionItem(
              id: '',
              title: title.trim(),
              category: widget.category,
              subcategory: resolvedSub,
              metadata: meta.isEmpty ? null : meta,
              imageUrl: resolvedImageUrl,
              isWishlist: options.isWishlist,
              quantity: options.quantity,
              locationId: options.locationId,
              groupId: options.groupId,
              locationUserId:
                  options.isWishlist ? null : options.locationUserId,
              minPlayers: resolvedMin,
              maxPlayers: resolvedMax,
              playingTime: resolvedTime,
            );

            await _insertCollectionItem(
              item: item,
              userId: userId,
              options: options,
            );
          }
        } else {
          final item = CollectionItem(
            id: '',
            title: title.trim(),
            category: widget.category,
            subcategory: resolvedSub,
            metadata: meta.isEmpty ? null : meta,
            imageUrl: resolvedImageUrl,
            isWishlist: options.isWishlist,
            quantity: options.quantity,
            locationId: options.locationId,
            groupId: options.groupId,
            locationUserId: options.isWishlist ? null : options.locationUserId,
            minPlayers: resolvedMin,
            maxPlayers: resolvedMax,
            playingTime: resolvedTime,
          );

          await _insertCollectionItem(
            item: item,
            userId: userId,
            options: options,
          );
        }
        if (options.isWishlist) {
          message = '« $title » ajouté à la wishlist';
        }
      }

      CollectionRefresh.instance.bump();

      if (!mounted) return;
      if (!dialogContext.mounted) return;
      Navigator.pop(dialogContext);
      if (closesTwoDialogs && context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = ProfileService.isMissingProfileFk(e)
            ? ProfileService.missingProfileUserMessage()
            : 'Impossible d\'ajouter : $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      rethrow;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ajouter : $e')),
        );
      }
      rethrow;
    }
  }

  Color get _onAccent {
    final c = _accentColor;
    return c.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
  }

  List<Widget> get _headerActions => [
        IconButton(
          icon: Icon(
            _viewMode == CollectionViewMode.grid
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded,
            color: _onAccent,
          ),
          tooltip: _viewMode == CollectionViewMode.grid
              ? 'Vue liste'
              : 'Vue grille',
          onPressed: () => setState(() {
            _viewMode = _viewMode == CollectionViewMode.grid
                ? CollectionViewMode.list
                : CollectionViewMode.grid;
          }),
        ),
        if (widget.category.supportsOpenLibrarySearch)
          IconButton(
            icon: Icon(Icons.qr_code_scanner_rounded, color: _onAccent),
            tooltip: 'Scanner ISBN',
            onPressed: _scanIsbnAndAdd,
          ),
      ];

  @override
  Widget build(BuildContext context) {
    if (widget.category == CollectionCategory.book) {
      if (widget.bookWishlistOnly) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.screenTitle ?? 'Wishlist Livres'),
            backgroundColor: _accentColor,
            foregroundColor: _onAccent,
          ),
          body: const BookWishlistTab(),
        );
      }
      return const BookCollectionScreen();
    }

    final title = widget.screenTitle ?? widget.category.label;

    return Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: _onAddPressed,
          backgroundColor: _accentColor,
          foregroundColor: _onAccent,
          tooltip: 'Ajouter',
          child: const Icon(Icons.add_rounded),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: Column(
          children: [
            CategoryCollectionHeader(
              category: widget.category,
              title: title,
              tabController: _tabController,
              accentOverride: widget.accentOverride,
              quickActions: _quickActions(),
              extraActions: _headerActions,
            ),
            Expanded(
              child: _itemsLoading && _enrichedItems == null
                  ? const Center(child: CircularProgressIndicator())
                  : _buildCollectionTabs(),
            ),
          ],
        ),
    );
  }

  List<CategoryQuickAction> _quickActions() {
    return switch (widget.category) {
      CollectionCategory.boardgame => [
          CategoryQuickAction(
            label: 'Tirage au sort',
            icon: Icons.casino_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => const ShakePickScreen(
                  category: CollectionCategory.boardgame,
                ),
              ),
            ),
          ),
          CategoryQuickAction(
            label: 'Historique parties',
            icon: Icons.history_edu,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => const GlobalPlayHistoryScreen(),
              ),
            ),
          ),
        ],
      CollectionCategory.book => [
          CategoryQuickAction(
            label: 'Rechercher',
            icon: Icons.menu_book_rounded,
            onTap: _showBookSearchDialog,
          ),
          CategoryQuickAction(
            label: 'Scan ISBN',
            icon: Icons.qr_code_scanner_rounded,
            onTap: _scanIsbnAndAdd,
          ),
        ],
      CollectionCategory.card => [
          CategoryQuickAction(
            label: 'Chercher une carte',
            icon: Icons.search_rounded,
            onTap: _showCardAddChooser,
          ),
        ],
      CollectionCategory.media => [
          CategoryQuickAction(
            label: 'Chercher / scanner',
            icon: Icons.album_rounded,
            onTap: _showMediaAddChooser,
          ),
        ],
      CollectionCategory.movie => [
          CategoryQuickAction(
            label: 'Chercher',
            icon: Icons.search_rounded,
            onTap: _showMovieAddChooser,
          ),
        ],
      CollectionCategory.videogame => [
          CategoryQuickAction(
            label: 'Chercher',
            icon: Icons.search_rounded,
            onTap: _showVideogameAddChooser,
          ),
        ],
      CollectionCategory.lego => [
          CategoryQuickAction(
            label: 'Chercher un set',
            icon: Icons.search_rounded,
            onTap: _showLegoAddChooser,
          ),
        ],
      _ => const <CategoryQuickAction>[],
    };
  }

  Map<String, int> _groupActivityCounts(List<CollectionItem> items) {
    final counts = <String, int>{};
    for (final item in items) {
      final extra = item.metadata?['group_ids'];
      if (extra is List) {
        for (final raw in extra) {
          final id = raw.toString();
          if (id.isNotEmpty) counts[id] = (counts[id] ?? 0) + 1;
        }
      }
      final gid = item.groupId;
      if (gid != null && gid.isNotEmpty) {
        counts[gid] = (counts[gid] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<CollectionItem>? _derivedCacheSource;
  Map<String, int> _collectionGroupActivity = const {};
  Map<String, int> _wishlistGroupActivity = const {};
  List<HolderFilterOption> _collectionHolderOptions = const [];

  void _syncDerivedCaches(
    List<CollectionItem> collection,
    List<CollectionItem> wishlist,
  ) {
    final source = _enrichedItems;
    if (identical(_derivedCacheSource, source)) return;
    _derivedCacheSource = source;
    if (widget.category == CollectionCategory.boardgame) {
      _collectionGroupActivity = _groupActivityCounts(collection);
      _wishlistGroupActivity = _groupActivityCounts(wishlist);
      _collectionHolderOptions = buildHolderFilterOptions(collection);
    } else {
      _collectionGroupActivity = const {};
      _wishlistGroupActivity = const {};
      _collectionHolderOptions = const [];
    }
  }

  Widget _buildCollectionTabs() {
    final allItems = _enrichedItems ?? _parseItems(_itemRows);
    final scoped = _filterHubScope(allItems);
    final rawCollection = scoped
        .where((item) => !item.isWishlist && isActiveCollectionItem(item))
        .toList();
    final collection = _visibleCollectionItems(rawCollection);
    final wishlist = scoped.where((item) => item.isWishlist).toList();
    final ownedIndex = buildOwnedQuantityIndex(scoped);
    _syncDerivedCaches(collection, wishlist);

    return TabBarView(
      controller: _tabController,
      children: [
        RepaintBoundary(
          child: CategoryCollectionTabPane(
          category: widget.category,
          fixedCardSubcategory: widget.fixedCardSubcategory,
          items: collection,
          ownedQuantityIndex: ownedIndex,
          groupActivityCounts: _collectionGroupActivity,
          holderFilterOptions: _collectionHolderOptions,
          groupNamesById: _groupNamesById,
          boardgameGroups: _groups,
          locations: _locations,
          tags: _tags,
          viewMode: _viewMode,
          mediaGroupByArtist: _mediaGroupByArtist,
          onMediaGroupByArtistChanged: (v) =>
              setState(() => _mediaGroupByArtist = v),
          emptyHint: 'Ta collection est vide ici.',
          showFocusFilter: true,
          showLocationFilter: widget.category != CollectionCategory.boardgame,
          showTagFilter: widget.category != CollectionCategory.boardgame,
          enableBulkSelection: true,
          currentUserId: _userId,
          onReload: _reloadItemsFromDb,
          onDeleteItem: _confirmDeleteItem,
          onBulkDeleteItems: _confirmBulkDeleteItems,
          onBggRatingSortEnrich: widget.category == CollectionCategory.boardgame
              ? () => _enrichBggRatingsForSort(
                    _filterHubScope(_parseItems(_itemRows)),
                  )
              : null,
        ),
        ),
        RepaintBoundary(
          child: CategoryCollectionTabPane(
          category: widget.category,
          fixedCardSubcategory: widget.fixedCardSubcategory,
          items: wishlist,
          ownedQuantityIndex: ownedIndex,
          groupActivityCounts: _wishlistGroupActivity,
          holderFilterOptions: const [],
          groupNamesById: _groupNamesById,
          boardgameGroups: _groups,
          locations: _locations,
          tags: _tags,
          viewMode: _viewMode,
          mediaGroupByArtist: _mediaGroupByArtist,
          onMediaGroupByArtistChanged: (v) =>
              setState(() => _mediaGroupByArtist = v),
          emptyHint: 'Rien en wishlist pour cette catégorie.',
          showFocusFilter: true,
          showLocationFilter: widget.category != CollectionCategory.boardgame,
          showTagFilter: widget.category != CollectionCategory.boardgame,
          showWishlistSuggestions:
              widget.category == CollectionCategory.boardgame,
          enableBulkSelection: true,
          defaultWishlistMineFilter: true,
          currentUserId: _userId,
          onReload: _reloadItemsFromDb,
          onDeleteItem: _confirmDeleteItem,
          onBulkDeleteItems: _confirmBulkDeleteItems,
        ),
        ),
      ],
    );
  }
}

int? _positivePlayingTime(dynamic value) {
  if (value is int) return value > 0 ? value : null;
  final parsed = int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : null;
}

