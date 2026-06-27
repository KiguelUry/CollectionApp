import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_subcategory.dart';
import '../models/category_metadata.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../models/item_condition.dart';
import '../services/group_service.dart';
import '../utils/supabase_embeds.dart';
import '../services/item_group_service.dart';
import '../services/loan_service.dart';
import '../services/collection_refresh.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/loan_item_dialog.dart';
import '../widgets/collection_cover_image.dart';
import '../widgets/cover_preview_sheet.dart';
import '../widgets/group_badge.dart';
import '../widgets/star_rating_bar.dart';
import '../widgets/assign_book_series_sheet.dart';
import '../widgets/item_tags_editor.dart';
import '../widgets/boardgame_expansions_section.dart';
import '../widgets/bgg_community_rating_panel.dart';
import '../models/boardgame_play_session.dart';
import '../widgets/boardgame_play_history_panel.dart';
import '../widgets/collapsible_section.dart';
import '../widgets/compact_whereabouts_dropdown.dart';
import '../widgets/discogs_market_value_card.dart';
import '../widgets/friend_ratings_panel.dart';
import '../widgets/group_rules_panel.dart';
import '../widgets/item_aspect_ratings_section.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/restaurant_visits_panel.dart';
import '../services/boardgame_expansion_service.dart';
import '../utils/boardgame_display.dart';
import '../utils/boardgame_collection_visibility.dart';
import '../utils/boardgame_expansion_flow.dart';
import '../utils/boardgame_expansions.dart';
import '../services/bgg_service.dart';
import '../services/global_play_history_service.dart';
import '../utils/copy_friend_item.dart';
import '../utils/friend_item_overlap.dart';
import '../utils/whereabouts_apply.dart';
import '../utils/whereabouts_persistence.dart';
import '../utils/owned_quantity_index.dart';
import '../utils/navigate_to_card_set.dart';
import '../utils/wishlist_promote.dart';
import 'package:url_launcher/url_launcher.dart';

class ItemDetailScreen extends StatefulWidget {
  final CollectionItem item;
  final int? ownedQuantity;
  final bool readOnly;
  final String? friendUsername;
  final FriendOverlapKind? friendOverlap;

  const ItemDetailScreen({
    super.key,
    required this.item,
    this.ownedQuantity,
    this.readOnly = false,
    this.friendUsername,
    this.friendOverlap,
  });

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final _loanService = LoanService();
  final _itemGroupService = ItemGroupService();
  late CollectionItem _item;
  late final TextEditingController _reviewController;
  late final TextEditingController _priceController;
  late final TextEditingController _gamesPlayedController;
  late final TextEditingController _personalRulesController;

  ItemCondition? _condition;
  List<CollectionGroup> _groups = [];
  Set<String> _selectedGroupIds = {};
  Timer? _saveDebounce;
  Timer? _quantityDebounce;
  bool _saveInFlight = false;
  bool _saveQueued = false;
  String? _bggDescription;
  bool _bggDescriptionLoading = false;
  int? _bggBestPlayers;
  double? _bggAvgRating;

  int _ownedDisplayQty = 0;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _ownedDisplayQty = widget.ownedQuantity ??
        (_item.isWishlist ? 0 : _item.quantity);
    _condition = _item.itemCondition;
    _reviewController = TextEditingController(text: _item.review ?? '');
    _priceController = TextEditingController(
      text: _item.purchasePrice?.toString() ?? '',
    );
    _gamesPlayedController = TextEditingController(
      text: _item.gamesPlayed?.toString() ?? '',
    );
    _personalRulesController = TextEditingController(
      text: _item.personalRules ?? '',
    );
    _syncGroupSelectionFromItem();
    _loadBggDescription();
    if (!widget.readOnly) {
      _reviewController.addListener(_scheduleSave);
      _priceController.addListener(_scheduleSave);
      _gamesPlayedController.addListener(_scheduleSave);
      _personalRulesController.addListener(_scheduleSave);
      _loadGroups();
      _loadGroupMembership();
      _reloadItem();
      if (widget.ownedQuantity == null && _item.isWishlist) {
        _resolveOwnedQuantity();
      }
    }
  }

  Future<void> _resolveOwnedQuantity() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('collection_items')
          .select('title, category, subcategory, metadata, quantity, is_wishlist, is_sold')
          .eq('category', _item.category.dbValue);
      final items = (rows as List)
          .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
          .toList();
      final idx = buildOwnedQuantityIndex(items);
      if (mounted) {
        setState(() => _ownedDisplayQty = ownedQuantityFor(_item, idx));
      }
    } catch (_) {}
  }

  Future<void> _loadBggDescription() async {
    if (_item.category != CollectionCategory.boardgame) return;

    final meta = _item.metadata;
    final bestFromMeta = parseBggBestPlayers(meta?['bgg_best_players']);
    final avgFromMeta = parseBggAvgRating(meta?['bgg_avg_rating']);
    if (mounted) {
      setState(() {
        if (bestFromMeta != null) _bggBestPlayers = bestFromMeta;
        if (avgFromMeta != null) _bggAvgRating = avgFromMeta;
      });
    }

    final shortFromMeta = meta?['bgg_short_description']?.toString().trim();
    if (shortFromMeta != null && shortFromMeta.isNotEmpty) {
      if (mounted) setState(() => _bggDescription = shortFromMeta);
      if (bestFromMeta != null && avgFromMeta != null) return;
    }

    final bggId = meta?['bgg_id']?.toString();
    if (bggId == null || bggId.isEmpty) return;

    if (mounted) setState(() => _bggDescriptionLoading = true);
    final details = await BggService.getGameFullDetails(bggId);
    if (!mounted) return;
    final short = details?['bgg_short_description']?.toString().trim();
    setState(() {
      if (short != null && short.isNotEmpty) {
        _bggDescription = short;
      }
      _bggBestPlayers =
          _bggBestPlayers ?? parseBggBestPlayers(details?['bgg_best_players']);
      _bggAvgRating =
          _bggAvgRating ?? parseBggAvgRating(details?['bgg_avg_rating']);
      _bggDescriptionLoading = false;
    });
    await _persistBggExtrasToMetadata(details);
  }

  Future<void> _persistBggExtrasToMetadata(
    Map<String, dynamic>? details,
  ) async {
    if (details == null || widget.readOnly) return;

    final meta = Map<String, dynamic>.from(_item.metadata ?? {});
    var dirty = false;
    for (final key in [
      'bgg_short_description',
      'bgg_avg_rating',
      'bgg_best_players',
    ]) {
      final v = details[key];
      if (v == null) continue;
      if (meta[key] == v) continue;
      meta[key] = v;
      dirty = true;
    }
    if (!dirty || !mounted) return;

    setState(() => _item = _item.copyWith(metadata: meta));
    try {
      await Supabase.instance.client
          .from('collection_items')
          .update({'metadata': meta})
          .eq('id', _item.id);
      CollectionRefresh.instance.bump();
    } catch (_) {}
  }

  Future<void> _loadGroupMembership() async {
    final ids = await _itemGroupService.fetchGroupIdsForItem(_item.id);
    if (!mounted || ids.isEmpty) return;
    setState(() {
      _selectedGroupIds = ids.toSet();
      _syncGroupSelectionFromItem();
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _quantityDebounce?.cancel();
    _reviewController.dispose();
    _priceController.dispose();
    _gamesPlayedController.dispose();
    _personalRulesController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    _groups = await GroupService().fetchMyGroups();
    if (mounted) setState(() {});
  }

  Future<Set<String>?> _pickGroups({Set<String>? initial}) async {
    if (_groups.isEmpty) return null;
    final selected = Set<String>.from(initial ?? _selectedGroupIds);

    return showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Choisir un ou plusieurs groupes',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: _groups.map((g) {
                          return CheckboxListTile(
                            value: selected.contains(g.id),
                            onChanged: (v) {
                              setModalState(() {
                                if (v == true) {
                                  selected.add(g.id);
                                } else {
                                  selected.remove(g.id);
                                }
                              });
                            },
                            title: GroupBadge.dropdownLabel(
                              name: g.name,
                              avatarUrl: g.avatarUrl,
                              accentColor: g.accentColor,
                              iconKey: g.iconKey,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(ctx, Set<String>.from(selected)),
                        child: Text(
                          selected.isEmpty ? 'Retirer des groupes' : 'Valider',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _groupAccent() {
    final gid = _item.groupId;
    if (gid == null) return Theme.of(context).colorScheme.primary;
    final group = _groups.where((g) => g.id == gid).firstOrNull;
    return ProfileAvatar.colorFromHex(group?.accentColor);
  }

  Future<void> _reloadItem() async {
    final row = await Supabase.instance.client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItemDetail)
        .eq('id', _item.id)
        .single();
    if (mounted) {
      setState(() {
        final reloaded = CollectionItem.fromJson(row);
        final localOwned = ownedExpansionBggIds(_item.metadata);
        final remoteOwned = ownedExpansionBggIds(reloaded.metadata);
        if (localOwned.length < remoteOwned.length) {
          final meta = metadataWithOwnedExpansions(
            reloaded.metadata,
            localOwned,
          );
          _item = reloaded.copyWith(metadata: meta);
        } else {
          _item = reloaded;
        }
        _syncGroupSelectionFromItem();
      });
    }
  }

  void _syncGroupSelectionFromItem() {
    _selectedGroupIds = {};
    if (_item.groupId != null) _selectedGroupIds.add(_item.groupId!);
    final extra = _item.metadata?['group_ids'];
    if (extra is List) {
      for (final id in extra) {
        if (id != null) _selectedGroupIds.add(id.toString());
      }
    }
    // Répare les anciennes lignes avec group_ids sans group_id en base.
    if (_item.groupId == null && _selectedGroupIds.isNotEmpty) {
      final first = _selectedGroupIds.first;
      _item = _item.copyWith(
        groupId: first,
        groupName: _groupNameById(first),
      );
    }
  }

  bool get _sharesWithGroup => _selectedGroupIds.isNotEmpty;

  Map<String, dynamic> _metadataWithGroups(List<String> groupIds) {
    final meta = Map<String, dynamic>.from(_item.metadata ?? {});
    if (groupIds.isNotEmpty) {
      meta['group_ids'] = groupIds;
    } else {
      meta.remove('group_ids');
    }
    return meta;
  }

  Map<String, dynamic> _metadataForSave(List<String> groupIds) {
    return buildWhereaboutsDbFields(_item, groupIds: groupIds)['metadata']
        as Map<String, dynamic>;
  }

  String? _groupNameById(String id) {
    for (final g in _groups) {
      if (g.id == id) return g.name;
    }
    return _item.groupName;
  }

  String _groupOwnershipSubtitle() {
    if (!_sharesWithGroup) return 'Personnel';
    final names = <String>[];
    for (final g in _groups) {
      if (_selectedGroupIds.contains(g.id)) names.add(g.name);
    }
    if (names.isEmpty) return _item.groupName ?? 'Groupe';
    return names.join(', ');
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 900), _save);
  }

  void _saveNow() {
    _saveDebounce?.cancel();
    _enqueueSave();
  }

  Future<void> _enqueueSave() async {
    if (_saveInFlight) {
      _saveQueued = true;
      return;
    }
    _saveInFlight = true;
    try {
      do {
        _saveQueued = false;
        await _save();
      } while (_saveQueued);
    } finally {
      _saveInFlight = false;
    }
  }

  void _adjustQuantity(int delta) {
    final minQ = _item.isWishlist ? 0 : 1;
    final next = (_item.quantity + delta).clamp(minQ, 9999);
    if (next == _item.quantity) return;
    setState(() => _item = _item.copyWith(quantity: next));
    _quantityDebounce?.cancel();
    _quantityDebounce = Timer(const Duration(milliseconds: 300), _saveNow);
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    final gamesPlayed = int.tryParse(_gamesPlayedController.text.trim());

    final groupIds = _selectedGroupIds.toList();
    _item = _item.copyWith(
      rating: _item.rating,
      review: _reviewController.text,
      purchasePrice: price,
      condition: _condition?.dbValue,
      gamesPlayed: gamesPlayed,
      personalRules: _personalRulesController.text,
      quantity: _item.quantity,
      locationId: _item.locationId,
      locationUserId: _item.locationUserId,
      groupId: groupIds.isEmpty ? null : groupIds.first,
      groupName: groupIds.isEmpty ? null : _groupNameById(groupIds.first),
      metadata: _metadataForSave(groupIds),
      isWishlist: _item.isWishlist,
      clearPurchasePrice: _priceController.text.trim().isEmpty,
      clearGamesPlayed: _gamesPlayedController.text.trim().isEmpty,
      clearGroup: groupIds.isEmpty,
    );

    try {
      final whereabouts = buildWhereaboutsDbFields(_item, groupIds: groupIds);
      final payload = _item.toUpdateJson();
      payload['metadata'] = whereabouts['metadata'];
      payload['location_user_id'] = whereabouts['location_user_id'];
      payload['group_id'] = groupIds.isEmpty ? null : groupIds.first;
      await Supabase.instance.client
          .from('collection_items')
          .update(payload)
          .eq('id', _item.id);
      await _itemGroupService.syncItemGroups(_item.id, groupIds);
      await _reloadItem();
      CollectionRefresh.instance.bump();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la sauvegarde : $e')),
        );
      }
    }
  }

  Future<void> _promoteFromWishlist() async {
    try {
      await promoteWishlistToCollection(_item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('« ${_item.title} » est dans ta collection')),
        );
        await _reloadItem();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  Future<void> _lend() async {
    if (_item.isWishlist || _item.isSold || _ownedDisplayQty <= 0) return;

    final result = await showLoanItemDialog(
      context: context,
      itemTitle: _item.title,
    );
    if (result == null || !mounted) return;

    try {
      final updated = result.profileId != null
          ? await _loanService.lendToFriend(
              itemId: _item.id,
              profileId: result.profileId!,
              displayName: result.displayName!,
            )
          : await _loanService.lendToExternal(
              itemId: _item.id,
              name: result.externalName!,
            );
      if (mounted) {
        setState(() => _item = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Prêté à ${updated.loaneeDisplayName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  Future<void> _returnLoan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Objet rendu ?'),
        content: Text(
          'Confirmer que « ${_item.title} » est de retour ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marquer rendu'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final updated = await _loanService.returnItem(_item.id);
      if (mounted) {
        setState(() => _item = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prêt clôturé')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  String? _loanSinceLabel() {
    final at = _item.loanedAt;
    if (at == null) return null;
    final d = at.toLocal();
    return 'Depuis le ${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('« ${_item.title} » sera retiré de la collection.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    if (_item.category == CollectionCategory.boardgame) {
      await GlobalPlayHistoryService().archivePlaysFromDeletedItem(_item);
    }

    await Supabase.instance.client
        .from('collection_items')
        .delete()
        .eq('id', _item.id);
    CollectionRefresh.instance.bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final metadataRows = CategoryMetadata.detailRows(_item);
    final isBoardgame = _item.category == CollectionCategory.boardgame;
    final isBook = _item.category == CollectionCategory.book;
    final isCard = _item.category == CollectionCategory.card;
    final cardSetName = _item.metadata?['set_name']?.toString().trim();
    final canOpenSet = isCard &&
        _item.cardSubcategory?.hasSetBrowser == true &&
        (_item.metadata?['set_id']?.toString().trim().isNotEmpty ?? false);
    final ro = widget.readOnly;
    final isWishlist = _item.isWishlist;
    final ownedQty = _ownedDisplayQty;

    final expansionOf = boardgameExpansionOfLabel(_item);

    return Scaffold(
      appBar: AppAppBar(
        title: _item.title,
        showBackButton: true,
        actions: [
          if (ro && widget.friendUsername != null)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Ajouter chez moi',
              onPressed: () => showCopyFriendItemSheet(
                context,
                source: _item,
                friendUsername: widget.friendUsername!,
              ),
            ),
          if (!ro && isBook && _item.volumeId == null)
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: 'Rattacher à une série',
              onPressed: () async {
                final sub = BookSubcategory.fromDbValue(_item.subcategory);
                final ok = await showAssignBookToSeriesSheet(
                  context,
                  item: _item,
                  subcategory: sub,
                );
                if (ok == true) _reloadItem();
              },
            ),
          if (!ro)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: _item.imageUrl != null
                        ? () => showCoverPreview(
                              context,
                              imageUrl: _item.imageUrl,
                              title: _item.title,
                              bookCover: isBook,
                            )
                        : null,
                    child: _item.imageUrl != null
                        ? SizedBox.expand(
                            child: CollectionCoverImage(
                              url: _item.imageUrl!,
                              height: 280,
                              bookCover: isBook,
                              boxedCover: isBook || isBoardgame || isCard,
                              largeSource: true,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Container(color: _item.category.color),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ro)
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.visibility, color: Colors.blue.shade700),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Collection d\'un ami — lecture seule',
                                  style: TextStyle(color: Colors.blue.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (ro) const SizedBox(height: 12),
                    if (!ro && isBoardgame && _item.isExpansion && expansionOf != null) ...[
                      Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Extension pour $expansionOf',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () async {
                                  final base = await promoteOrphanExpansionToBase(
                                    orphanExpansion: _item,
                                  );
                                  if (!mounted || base == null) return;
                                  if (!context.mounted) return;
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) =>
                                          ItemDetailScreen(item: base),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.link),
                                label: const Text('Ajouter / lier le jeu de base'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (ro &&
                        widget.friendOverlap != null &&
                        widget.friendOverlap != FriendOverlapKind.none)
                      Card(
                        color: widget.friendOverlap ==
                                FriendOverlapKind.inCollection
                            ? Colors.green.shade50
                            : Colors.amber.shade50,
                        child: ListTile(
                          leading: Icon(
                            widget.friendOverlap ==
                                    FriendOverlapKind.inCollection
                                ? Icons.check_circle_outline
                                : Icons.favorite_border,
                            color: widget.friendOverlap ==
                                    FriendOverlapKind.inCollection
                                ? Colors.green.shade700
                                : Colors.amber.shade800,
                          ),
                          title: Text(
                            widget.friendOverlap ==
                                    FriendOverlapKind.inCollection
                                ? 'Tu as déjà cet objet'
                                : 'Déjà dans ta wishlist',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Utilise + en haut pour l\'ajouter ou compléter ta collection',
                          ),
                        ),
                      ),
                    if (ro &&
                        widget.friendOverlap != null &&
                        widget.friendOverlap != FriendOverlapKind.none)
                      const SizedBox(height: 12),
                    if (!ro && isWishlist) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _promoteFromWishlist,
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Je l\'ai — ajouter à ma collection'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(_item.category.icon, size: 18),
                          label: Text(_item.category.label),
                        ),
                        if (_item.bookSubcategory != null)
                          Chip(label: Text(_item.bookSubcategory!.label)),
                        if (_item.cardSubcategory != null)
                          Chip(label: Text(_item.cardSubcategory!.label)),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (_item.createdAtLabel != null)
                            Expanded(
                              child: Text(
                                _item.createdAtLabel!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          Text(
                            'Possédé : $ownedQty',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!isWishlist && !ro) ...[
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: _item.quantity > 1
                                  ? () => _adjustQuantity(-1)
                                  : null,
                              icon: const Icon(Icons.remove, size: 20),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _adjustQuantity(1),
                              icon: const Icon(Icons.add, size: 20),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isWishlist && ownedQty == 0)
                      Text(
                        'Tu peux enregistrer des parties même sans posséder le jeu.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      )
                    else if (isWishlist && ownedQty > 0)
                      Text(
                        'Tu possèdes déjà $ownedQty exemplaire${ownedQty > 1 ? 's' : ''} en collection.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      )
                    else if (_groupOwnershipSubtitle().isNotEmpty)
                      Text(
                        _groupOwnershipSubtitle(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    if (!isBoardgame && !isWishlist && !isCard) ...[
                      const SizedBox(height: 12),
                      CollapsibleSection(
                        title: 'Tags',
                        accentColor: _item.category.color,
                        child: ItemTagsEditor(
                          itemId: _item.id,
                          initialTags: _item.tags,
                          readOnly: ro,
                        ),
                      ),
                    ],
                    if (canOpenSet) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => openCardSetCatalog(context, _item),
                          icon: const Icon(Icons.layers_outlined),
                          label: Text(
                            cardSetName != null && cardSetName.isNotEmpty
                                ? 'Voir la série $cardSetName'
                                : 'Voir la série',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (isBoardgame) ...[
                      _buildBggDescriptionSection(),
                      if (_bggDescriptionLoading ||
                          (_bggDescription != null &&
                              _bggDescription!.isNotEmpty))
                        const SizedBox(height: 16),
                    ],
                    _buildInformationsSection(
                      isBoardgame: isBoardgame,
                      metadataRows: metadataRows,
                    ),
                    if (isBoardgame) ...[
                      const SizedBox(height: 12),
                      CollapsibleSection(
                        title: 'Jeu de société',
                        accentColor: _item.category.color,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BoardgamePlayHistoryPanel(
                              item: _item,
                              readOnly: ro,
                              onMetadataChanged: (meta) {
                                final count = parseBoardgamePlays(meta).length;
                                setState(() {
                                  _item = _item.copyWith(metadata: meta);
                                  _gamesPlayedController.text =
                                      count > 0 ? count.toString() : '';
                                });
                                _saveNow();
                              },
                            ),
                            if (!isWishlist) ...[
                              const SizedBox(height: 12),
                              if (_item.groupId != null)
                                GroupRulesPanel(
                                  groupId: _item.groupId!,
                                  itemId: _item.id,
                                  itemTitle: _item.title,
                                  accent: _groupAccent(),
                                )
                              else
                                TextField(
                                  controller: _personalRulesController,
                                  readOnly: ro,
                                  maxLines: 5,
                                  decoration: const InputDecoration(
                                    labelText: 'Règles personnalisées',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (isBoardgame && BoardgameExpansionService.itemActsAsBase(_item))
                      CollapsibleSection(
                        title: 'Extensions',
                        accentColor: _item.category.color,
                        child: BoardgameExpansionsSection(
                          item: _item,
                          readOnly: ro,
                          onItemUpdated: (updated) =>
                              setState(() => _item = updated),
                        ),
                      ),
                    if (!isWishlist) ...[
                      CollapsibleSection(
                        title: 'Partage & groupes',
                        accentColor: _item.category.color,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!ro)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    if (_groups.isEmpty) await _loadGroups();
                                    if (!mounted) return;
                                    if (_groups.isEmpty) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Crée d\'abord un groupe dans le menu « Groupes »',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    final picked = await _pickGroups(
                                      initial: _selectedGroupIds,
                                    );
                                    if (!mounted || picked == null) return;
                                    if (picked.isEmpty) {
                                      setState(() {
                                        _selectedGroupIds = {};
                                        _item = _item.copyWith(clearGroup: true);
                                      });
                                    } else {
                                      final first = picked.first;
                                      final g = _groups
                                          .firstWhere((x) => x.id == first);
                                      setState(() {
                                        _selectedGroupIds = picked;
                                        _item = _item.copyWith(
                                          groupId: first,
                                          groupName: g.name,
                                          metadata: _metadataWithGroups(
                                            picked.toList(),
                                          ),
                                          clearLocation: true,
                                        );
                                      });
                                    }
                                    _saveNow();
                                  },
                                  icon: const Icon(Icons.group_outlined, size: 18),
                                  label: const Text('Gestion des groupes'),
                                ),
                              ),
                            if (_selectedGroupIds.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: _groups
                                    .where(
                                      (g) => _selectedGroupIds.contains(g.id),
                                    )
                                    .map(
                                      (g) => Chip(
                                        label: Text(g.name),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 12),
                            CompactWhereaboutsDropdown(
                              groups: _groups,
                              selectedGroupIds: _selectedGroupIds,
                              locationUserId: _item.locationUserId,
                              holderLabel: _item.locationLabel,
                              readOnly: ro,
                              applyDefaultIfEmpty: !itemHasManualHolder(_item),
                              onChanged: ({
                                locationUserId,
                                holderLabel,
                                clearHolder = false,
                                manualHolder = false,
                              }) {
                                setState(() {
                                  _item = applyWhereaboutsChange(
                                    _item,
                                    locationUserId: locationUserId,
                                    holderLabel: holderLabel,
                                    clearHolder: clearHolder,
                                    manualHolder: manualHolder,
                                  );
                                });
                                if (manualHolder || locationUserId != null) {
                                  _saveNow();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isBook && !_item.isWishlist && !_item.isSold) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Lu'),
                        value: _item.isRead,
                        onChanged: ro
                            ? null
                            : (v) {
                                setState(() => _item = _item.copyWith(isRead: v));
                                _saveNow();
                              },
                      ),
                    ],
                    CollapsibleSection(
                      title: 'Ma note & avis',
                      accentColor: _item.category.color,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StarRatingBar(
                            rating: _item.rating ?? 0,
                            onChanged: ro
                                ? (_) {}
                                : (value) {
                                    setState(() {
                                      _item = _item.copyWith(
                                        rating: value <= 0 ? null : value,
                                        clearRating: value <= 0,
                                      );
                                    });
                                    _saveNow();
                                  },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _reviewController,
                            readOnly: ro,
                            maxLines: 2,
                            minLines: 1,
                            decoration: const InputDecoration(
                              labelText: 'Mon avis',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ItemAspectRatingsSection(
                            category: _item.category,
                            metadata: _item.metadata,
                            readOnly: ro,
                            onMetadataChanged: (meta) {
                              setState(() => _item = _item.copyWith(metadata: meta));
                              _saveNow();
                            },
                          ),
                          if (isBoardgame) ...[
                            const SizedBox(height: 16),
                            BggCommunityRatingPanel(
                              avgRating: _bggAvgRating ??
                                  parseBggAvgRating(
                                    _item.metadata?['bgg_avg_rating'],
                                  ),
                              loading: _bggDescriptionLoading,
                            ),
                          ],
                          if (!ro) ...[
                            const SizedBox(height: 16),
                            FriendRatingsPanel(item: _item),
                          ],
                        ],
                      ),
                    ),
                    if (_item.category == CollectionCategory.media &&
                        !isWishlist) ...[
                      const SizedBox(height: 16),
                      DiscogsMarketValueCard(
                        releaseId:
                            _item.metadata?['discogs_release_id']?.toString(),
                        artist: _item.metadata?['artist']?.toString(),
                        albumTitle: _item.title,
                      ),
                    ],
                    if (_item.category == CollectionCategory.restaurant &&
                        !ro) ...[
                      const Divider(height: 28),
                      RestaurantVisitsPanel(item: _item),
                    ],
                    if (!ro && !_item.isGroupOwned) ...[
                    const Divider(height: 28),
                    _buildSectionTitle('Prêt'),
                    if (_item.isOnLoan) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.handshake,
                          color: Colors.blue.shade700,
                        ),
                        title: Text('Prêté à ${_item.loaneeDisplayName}'),
                        subtitle: Text(
                          [
                            if (_loanSinceLabel() != null) _loanSinceLabel()!,
                            if (_item.loanedToId != null) 'Ami sur l\'app',
                            if (_item.loanedToId == null) 'Hors app',
                          ].join(' · '),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _returnLoan,
                        icon: const Icon(Icons.undo),
                        label: const Text('Marquer comme rendu'),
                      ),
                    ] else if (!_item.isSold && ownedQty > 0)
                      FilledButton.icon(
                        onPressed: _lend,
                        icon: const Icon(Icons.handshake_outlined),
                        label: const Text('Prêter cet objet'),
                      )
                    else
                      Text(
                        ownedQty == 0
                            ? 'Tu ne peux pas prêter un objet que tu ne possèdes pas.'
                            : 'Les objets en wishlist ou vendus ne peuvent pas être prêtés.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    if (!ro && !isWishlist && ownedQty > 0) ...[
                    CollapsibleSection(
                      title: 'Doubles & vente',
                      accentColor: _item.category.color,
                      initiallyExpanded: false,
                      child: Column(
                        children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('À vendre / échanger'),
                      subtitle: const Text(
                        'Apparaît dans l\'onglet « À vendre »',
                      ),
                      value: _item.isForSale && !_item.isSold,
                      onChanged: _item.isSold
                          ? null
                          : (v) {
                              setState(() {
                                _item = _item.copyWith(
                                  isForSale: v,
                                  isSold: false,
                                );
                              });
                              _saveNow();
                            },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Marquer comme vendu'),
                      subtitle: const Text(
                        'Retire de la collection active, tuile grisée dans l\'historique',
                      ),
                      value: _item.isSold,
                      onChanged: (v) {
                        setState(() {
                          _item = _item.copyWith(
                            isSold: v,
                            isForSale: v ? false : _item.isForSale,
                          );
                        });
                        _saveNow();
                      },
                    ),
                        ],
                      ),
                    ),
                    ],
                    if (isWishlist && isBoardgame) ...[
                      const Divider(height: 28),
                      _buildSectionTitle('Prix marché (indicatif)'),
                      Text(
                        'Consulte BoardGameGeek pour une fourchette de prix neuf / occasion.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    if (!isWishlist) ...[
                    CollapsibleSection(
                      title: 'Valeur & état',
                      accentColor: _item.category.color,
                      initiallyExpanded: false,
                      child: Column(
                        children: [
                    TextField(
                      controller: _priceController,
                      readOnly: ro,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Prix d\'achat (€)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ItemCondition?>(
                      initialValue: _condition,
                      decoration: const InputDecoration(
                        labelText: 'État',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<ItemCondition?>(
                          value: null,
                          child: Text('— Non renseigné —'),
                        ),
                        ...ItemCondition.values.map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.label),
                          ),
                        ),
                      ],
                      onChanged: ro
                          ? null
                          : (val) {
                              setState(() => _condition = val);
                              _scheduleSave();
                            },
                    ),
                        ],
                      ),
                    ),
                    ],
                    if (!isBoardgame || isWishlist) ...[
                      const Divider(height: 28),
                      _buildSectionTitle('Notes'),
                      TextField(
                        controller: _personalRulesController,
                        readOnly: ro,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notes personnelles',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildBggDescriptionSection() {
    if (_bggDescriptionLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final text = _bggDescription;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.lora(
        fontSize: 15,
        height: 1.55,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
      ),
    );
  }

  Widget _buildInformationsSection({
    required bool isBoardgame,
    required List<MapEntry<String, String>> metadataRows,
  }) {
    final m = _item.metadata ?? {};
    final players = formatPlayerCount(_item.minPlayers, _item.maxPlayers);
    final bestPlayersLabel = formatBggBestPlayersLabel(
      _bggBestPlayers ?? parseBggBestPlayers(m['bgg_best_players']),
    );
    final time = formatPlayingTime(_item.playingTime);
    final bggId = m['bgg_id']?.toString();
    final bggPageUrl = BggService.gamePageUrl(bggId);
    final year = m['year_published'] ?? m['year'];
    final minAge = m['min_age'];
    final boardAccent = Colors.orange.shade800;

    final extraRows = isBoardgame
        ? metadataRows
            .where((r) => r.key != 'Parution' && r.key != 'Âge')
            .toList()
        : metadataRows;

    if (!isBoardgame && extraRows.isEmpty) {
      return const SizedBox.shrink();
    }
    if (isBoardgame &&
        players == null &&
        time == null &&
        year == null &&
        minAge == null &&
        extraRows.isEmpty &&
        bggPageUrl == null) {
      return const SizedBox.shrink();
    }

    final boardTiles = <Widget>[];
    if (isBoardgame) {
      if (players != null) {
        boardTiles.add(
          _infoTile(
            Icons.people,
            players,
            boardAccent,
            bestPlayersLabel,
          ),
        );
      }
      if (time != null) {
        boardTiles.add(_infoTile(Icons.timer, time, boardAccent));
      }
      if (year != null && year.toString().isNotEmpty) {
        boardTiles.add(
          _infoTile(Icons.calendar_today, year.toString(), boardAccent),
        );
      }
      if (minAge != null) {
        boardTiles.add(_infoTile(Icons.child_care, '$minAge+', boardAccent));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Informations'),
        if (boardTiles.isNotEmpty) ...[
          if (boardTiles.length >= 2)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: boardTiles.take(2).toList(),
            ),
          if (boardTiles.length > 2) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: boardTiles.skip(2).take(2).toList(),
            ),
          ] else if (boardTiles.length == 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: boardTiles,
            ),
          if (extraRows.isNotEmpty) const SizedBox(height: 12),
        ],
        ...extraRows.map(
          (row) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              row.key,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
            subtitle: Text(
              row.value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (bggPageUrl != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(bggPageUrl);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Voir sur BoardGameGeek'),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: _item.category.color,
        ),
      ),
    );
  }

  Widget _infoTile(
    IconData icon,
    String label, [
    Color? iconColor,
    String? subtitle,
  ]) {
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          Icon(icon, color: iconColor ?? Colors.deepPurple, size: 26),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
