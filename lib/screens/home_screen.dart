import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_subcategory.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../models/card_subcategory.dart';
import '../models/category_metadata.dart';
import '../models/media_format_ui.dart';
import '../services/bgg_service.dart';
import '../services/book_catalog_service.dart';
import '../services/card_catalog_service.dart';
import '../services/media_catalog_service.dart';
import '../services/profile_service.dart';
import '../utils/boardgame_genres.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_item_filters.dart';
import '../utils/card_item_metadata.dart';
import '../utils/collection_item_scope.dart';
import '../models/collection_list_filters.dart';
import '../models/collection_view_mode.dart';
import '../models/item_tag.dart';
import '../models/storage_location.dart';
import '../services/location_service.dart';
import '../services/tag_service.dart';
import '../widgets/category_collection_header.dart';
import '../widgets/category_collection_shell.dart';
import '../widgets/collection_filter_bar.dart';
import '../widgets/wishlist_suggestions_banner.dart';
import '../widgets/collection_item_list_tile.dart';
import '../widgets/collection_item_tile.dart';
import '../widgets/isbn_scan_sheet.dart';
import 'shake_pick_screen.dart';
import '../widgets/add_item_manual_dialog.dart';
import '../widgets/add_item_options_dialog.dart';
import '../widgets/bgg_search_dialog.dart';
import '../widgets/book_search_dialog.dart' show showBookSearch;
import '../widgets/card_search_dialog.dart' show showCardSearch;
import '../widgets/media_search_dialog.dart' show showMediaSearch;
import '../widgets/ui/add_option_tile.dart';
import '../models/lego_build_kind.dart';
import '../services/rebrickable_service.dart';
import '../services/rawg_service.dart';
import '../services/tmdb_service.dart';
import '../utils/catalog_hit_metadata.dart';
import '../widgets/book_subcategory_picker.dart';
import '../widgets/catalog_search_sheet.dart';
import 'item_detail_screen.dart';
import 'media_artist_albums_screen.dart';

class HomeScreen extends StatefulWidget {
  final CollectionCategory category;
  final String? screenTitle;
  final CardSubcategory? fixedCardSubcategory;
  final MediaFormat? fixedMediaFormat;

  final Color? accentOverride;
  final String? customTypeId;
  final String? customTypeName;
  final LegoBuildKind? fixedLegoKind;
  final Map<String, String>? pendingCatalogHit;

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
    this.pendingCatalogHit,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _tagService = TagService();
  final _collectionSearch = TextEditingController();
  final _wishlistSearch = TextEditingController();
  late final TabController _tabController;

  late final String _userId;
  late final Stream<List<Map<String, dynamic>>> _itemsStream;
  CollectionListFilters _collectionFilters = CollectionListFilters();
  CollectionListFilters _wishlistFilters = CollectionListFilters();
  CollectionViewMode _viewMode = CollectionViewMode.grid;
  bool _mediaGroupByArtist = false;
  List<StorageLocation> _locations = [];
  List<ItemTag> _tags = [];

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
    _loadFilterData();
    if (widget.pendingCatalogHit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openFromCatalogHit(widget.pendingCatalogHit!);
      });
    }
  }

  List<Map<String, dynamic>> _filterAndScopeRows(
    List<Map<String, dynamic>> rows,
  ) {
    var filtered = _onlyMyRows(rows);

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
    _tabController.dispose();
    _collectionSearch.dispose();
    _wishlistSearch.dispose();
    super.dispose();
  }

  bool get _addingToWishlist => _tabController.index == 1;

  Future<void> _loadFilterData() async {
    try {
      final locs = await LocationService().fetchLocations();
      final tags = await _tagService.fetchMyTags();
      if (mounted) {
        setState(() {
          _locations = locs;
          _tags = tags;
        });
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

  List<Map<String, dynamic>> _onlyMyRows(List<Map<String, dynamic>> rows) {
    return rows.where((row) {
      final addedBy = row['added_by'] as String?;
      final locUser = row['location_user_id'] as String?;
      return addedBy == _userId || locUser == _userId;
    }).toList();
  }

  void _onAddPressed() {
    if (widget.category.supportsBggSearch) {
      if (kIsWeb) {
        _showBoardgameAddChooser();
      } else {
        _showBggSearchDialog();
      }
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
          title: 'Rechercher un film ou une série',
          hint: 'Titre',
          apiHint: TmdbService.isConfigured
              ? null
              : 'Ajoute TMDB_API_KEY dans .env',
          search: TmdbService.search,
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
          apiHint: RawgService.isConfigured
              ? null
              : 'Ajoute RAWG_API_KEY dans .env',
          search: RawgService.search,
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
          hint: 'Nom ou n° de set',
          apiHint: RebrickableService.isConfigured
              ? null
              : 'Ajoute REBRICKABLE_API_KEY dans .env',
          search: RebrickableService.search,
          onManualEntry: () => _showManualAddFlow(
            legoKind: widget.fixedLegoKind,
          ),
        ).then((hit) {
          if (hit != null && mounted) _openFromCatalogHit(hit);
        });
      },
    );
  }

  void _showBoardgameAddChooser() {
    final proxyOk = BggService.webBggAvailable;
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
              subtitle: Text(
                proxyOk
                    ? 'Recherche complète (via Supabase)'
                    : 'Indisponible : déploie la fonction bgg-proxy (voir README Supabase)',
              ),
              enabled: proxyOk,
              onTap: proxyOk
                  ? () {
                      Navigator.pop(ctx);
                      _showBggSearchDialog();
                    }
                  : null,
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
    return items;
  }

  Future<void> _showManualAddFlow({
    CardSubcategory? cardSubcategory,
    MediaFormat? mediaFormat,
    LegoBuildKind? legoKind,
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
        lockSubcategory: widget.fixedCardSubcategory != null ||
            widget.fixedMediaFormat != null ||
            widget.fixedLegoKind != null,
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
        resolvedTime = bggDetails['playing_time'] as int?;
      } else if (bggId != null) {
        final details = await BggService.getGameFullDetails(bggId);
        resolvedImageUrl =
            (details?['image_url'] as String?) ?? resolvedImageUrl;
        resolvedMin = details?['min_players'] as int?;
        resolvedMax = details?['max_players'] as int?;
        resolvedTime = details?['playing_time'] as int?;
      }

      var dupQuery = client
          .from('collection_items')
          .select('id, quantity')
          .eq('category', widget.category.dbValue)
          .eq('title', title.trim());

      final resolvedSub = widget.customTypeId ?? subcategory;
      if (resolvedSub != null) {
        dupQuery = dupQuery.eq('subcategory', resolvedSub);
      }

      if (options.groupId != null) {
        dupQuery = dupQuery.eq('group_id', options.groupId!);
      } else {
        dupQuery = dupQuery
            .filter('group_id', 'is', null)
            .or(CollectionItemScope.personalOrFilter(userId));
      }

      final existing = await dupQuery.maybeSingle();
      var message = '« $title » ajouté';
      if (existing != null) {
        final newQty =
            ((existing['quantity'] as int?) ?? 1) + options.quantity;
        await client
            .from('collection_items')
            .update({'quantity': newQty})
            .eq('id', existing['id']);
        message = 'Quantité mise à jour ($newQty)';
      } else {
        final meta = Map<String, dynamic>.from(metadata ?? {});
        if (options.holderLabel != null &&
            options.holderLabel!.trim().isNotEmpty) {
          meta['holder_label'] = options.holderLabel!.trim();
        }
        if (bggId != null) meta['bgg_id'] = bggId;
        if (bggDetails != null) {
          for (final key in [
            'year_published',
            'min_age',
            'bgg_categories',
          ]) {
            final v = bggDetails[key];
            if (v != null) meta[key] = v;
          }
        }
        if (widget.fixedLegoKind != null && !meta.containsKey('lego_kind')) {
          meta['lego_kind'] = widget.fixedLegoKind!.dbValue;
        }
        if (widget.customTypeName != null) {
          meta['custom_type_name'] = widget.customTypeName;
        }

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
          minPlayers: resolvedMin,
          maxPlayers: resolvedMax,
          playingTime: resolvedTime,
        );

        await client.from('collection_items').insert(
              item.toInsertJson(
                isWishlist: options.isWishlist,
                locationUserId: options.isWishlist
                    ? null
                    : (options.locationUserId ?? userId),
                addedBy: userId,
              ),
            );
        if (options.isWishlist) {
          message = '« $title » ajouté à la wishlist';
        }
      }

      if (!mounted) return;
      Navigator.pop(dialogContext);
      if (closesTwoDialogs && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
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
    final title = widget.screenTitle ?? widget.category.label;

    return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _onAddPressed,
          backgroundColor: _accentColor,
          foregroundColor: _onAccent,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Ajouter'),
        ),
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
              child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _itemsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Erreur : ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            return FutureBuilder<List<CollectionItem>>(
              future: _tagService.enrichItems(
                snapshot.data!
                    .map((json) => CollectionItem.fromJson(json))
                    .toList(),
              ),
              builder: (context, enrichedSnap) {
                final allItems = enrichedSnap.data ??
                    snapshot.data!
                        .map((json) => CollectionItem.fromJson(json))
                        .toList();
                final scoped = _filterHubScope(allItems);
                final collection = scoped
                    .where((item) =>
                        !item.isWishlist && isActiveCollectionItem(item))
                    .toList();
                final wishlist = scoped.where((item) => item.isWishlist).toList();

                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTab(
                      items: collection,
                      filters: _collectionFilters,
                      searchController: _collectionSearch,
                      onFiltersChanged: (f) =>
                          setState(() => _collectionFilters = f),
                      emptyHint: 'Ta collection est vide ici.',
                      showScopeFilters: true,
                      showLocationFilter:
                          widget.category != CollectionCategory.boardgame,
                      showTagFilter:
                          widget.category != CollectionCategory.boardgame,
                    ),
                    _buildTab(
                      items: wishlist,
                      filters: _wishlistFilters,
                      searchController: _wishlistSearch,
                      onFiltersChanged: (f) =>
                          setState(() => _wishlistFilters = f),
                      emptyHint: 'Rien en wishlist pour cette catégorie.',
                      showScopeFilters: true,
                      showLocationFilter:
                          widget.category != CollectionCategory.boardgame,
                      showTagFilter:
                          widget.category != CollectionCategory.boardgame,
                      showWishlistSuggestions:
                          widget.category == CollectionCategory.boardgame,
                    ),
                  ],
                );
              },
            );
          },
        ),
            ),
          ],
        ),
    );
  }

  List<CategoryQuickAction> _quickActions() {
    return switch (widget.category) {
      CollectionCategory.boardgame => [
          CategoryQuickAction(
            label: 'Chercher BGG',
            icon: Icons.search_rounded,
            onTap: () {
              if (kIsWeb && !BggService.webBggAvailable) {
                _showBoardgameAddChooser();
              } else {
                _showBggSearchDialog();
              }
            },
          ),
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

  String _buildCountLabel(List<CollectionItem> items, List<CollectionItem> filtered) {
    if (filtered.length != items.length) {
      return '${filtered.length} sur ${items.length}';
    }
    final personal = items.where((i) => !i.isGroupOwned).length;
    final inGroup = items.length - personal;
    if (inGroup > 0 && personal > 0) {
      return '$personal objet${personal > 1 ? 's' : ''} · $inGroup en groupe${inGroup > 1 ? 's' : ''}';
    }
    return '${items.length} objet${items.length > 1 ? 's' : ''}';
  }

  Widget _buildTab({
    required List<CollectionItem> items,
    required CollectionListFilters filters,
    required TextEditingController searchController,
    required ValueChanged<CollectionListFilters> onFiltersChanged,
    required String emptyHint,
    bool showScopeFilters = true,
    bool showLocationFilter = true,
    bool showTagFilter = true,
    bool showWishlistSuggestions = false,
  }) {
    final filtered = filters.apply(items);
    final countLabel = _buildCountLabel(items, filtered);
    final groupOptions = items
        .where((i) => i.groupId != null)
        .map((i) => MapEntry(i.groupId!, i.groupName ?? 'Groupe'))
        .fold<Map<String, String>>(
          <String, String>{},
          (acc, entry) => acc..putIfAbsent(entry.key, () => entry.value),
        )
        .entries
        .map((e) => GroupFilterOption(id: e.key, label: e.value))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    final cardRarityOptions = widget.category == CollectionCategory.card
        ? (distinctCardRarities(items).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
        : const <String>[];
    final pokemonTypeOptions = widget.category == CollectionCategory.card
        ? (distinctPokemonTypes(items).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showWishlistSuggestions)
          WishlistSuggestionsBanner(category: widget.category),
        if (widget.category == CollectionCategory.media)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Par artiste'),
                selected: _mediaGroupByArtist,
                onSelected: (v) => setState(() => _mediaGroupByArtist = v),
                avatar: const Icon(Icons.person_outline, size: 18),
              ),
            ),
          ),
        CollectionFilterBar(
          filters: filters,
          onChanged: onFiltersChanged,
          searchController: searchController,
          locations: _locations,
          tags: _tags,
          showScopeFilters: showScopeFilters,
          showLocationFilter: showLocationFilter,
          showTagFilter: showTagFilter,
          showBoardgameGenreFilter:
              widget.category == CollectionCategory.boardgame,
          boardgameGenres: widget.category == CollectionCategory.boardgame
              ? distinctBoardgameGenres(items)
              : const [],
          showCardFilter: widget.category == CollectionCategory.card,
          cardRarities: cardRarityOptions,
          pokemonTypes: pokemonTypeOptions,
          groupOptions: groupOptions,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Text(
            countLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: widget.category == CollectionCategory.media &&
                  _mediaGroupByArtist
              ? _buildMediaArtistList(filtered, emptyHint: emptyHint)
              : _viewMode == CollectionViewMode.grid
                  ? _buildItemGrid(
                      filtered,
                      emptyHint: emptyHint,
                      filters: filters,
                      onClearFilters: () {
                        searchController.clear();
                        onFiltersChanged(CollectionListFilters());
                      },
                    )
                  : _buildItemList(
                      filtered,
                      emptyHint: emptyHint,
                      filters: filters,
                      onClearFilters: () {
                        searchController.clear();
                        onFiltersChanged(CollectionListFilters());
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildMediaArtistList(
    List<CollectionItem> items, {
    required String emptyHint,
  }) {
    if (items.isEmpty) {
      return Center(child: Text(emptyHint));
    }

    final byArtist = <String, List<CollectionItem>>{};
    for (final item in items) {
      final raw = item.metadata?['artist']?.toString().trim();
      final key =
          raw != null && raw.isNotEmpty ? raw : 'Artiste inconnu';
      byArtist.putIfAbsent(key, () => []).add(item);
    }
    final artists = byArtist.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: artists.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final name = artists[index];
        final albums = byArtist[name]!;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: widget.category.color.withValues(alpha: 0.2),
            child: Icon(Icons.person, color: widget.category.color),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${albums.length} album${albums.length > 1 ? 's' : ''}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => MediaArtistAlbumsScreen(
                artist: name,
                items: albums,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemGrid(
    List<CollectionItem> items, {
    required String emptyHint,
    required CollectionListFilters filters,
    required VoidCallback onClearFilters,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                emptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (filters.hasActiveFilters) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onClearFilters,
                  child: const Text('Réinitialiser les filtres'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final grouped = CollectionGridGrouper.group(items);

    final aspectRatio = switch (widget.category) {
      CollectionCategory.boardgame => 0.72,
      CollectionCategory.card => 0.5,
      _ => 0.85,
    };

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: aspectRatio,
      ),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final entry = grouped[index];
        final item = entry.item;

        return CollectionItemTile(
          item: item,
          category: widget.category,
          totalQuantity: entry.totalQuantity,
          showDuplicateBadge: entry.hasDuplicates,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ItemDetailScreen(
                item: item.copyWith(quantity: entry.totalQuantity),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemList(
    List<CollectionItem> items, {
    required String emptyHint,
    required CollectionListFilters filters,
    required VoidCallback onClearFilters,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                emptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (filters.hasActiveFilters) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onClearFilters,
                  child: const Text('Réinitialiser les filtres'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final grouped = CollectionGridGrouper.group(items);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final entry = grouped[index];
        final item = entry.item;
        return CollectionItemListTile(
          item: item,
          category: widget.category,
          totalQuantity: entry.totalQuantity,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ItemDetailScreen(
                item: item.copyWith(quantity: entry.totalQuantity),
              ),
            ),
          ),
        );
      },
    );
  }
}
