import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_subcategory.dart';
import '../models/category_metadata.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../models/item_condition.dart';
import '../services/group_service.dart';
import '../services/activity_service.dart';
import '../services/bgg_service.dart';
import '../services/pantheon_memory.dart';
import '../services/profile_service.dart';
import '../utils/pantheon_ranking.dart';
import '../widgets/bgg_photo_strip.dart';
import '../utils/bgg_text.dart';
import '../utils/supabase_embeds.dart';
import '../services/item_group_service.dart';
import '../services/loan_service.dart';
import '../services/collection_refresh.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/loan_item_dialog.dart';
import '../widgets/collection_cover_image.dart';
import '../widgets/cover_preview_sheet.dart';
import '../widgets/group_badge.dart';
import '../widgets/precision_star_rating_bar.dart';
import '../services/owned_catalog_index.dart';
import '../widgets/assign_book_series_sheet.dart';
import '../widgets/item_tags_editor.dart';
import '../widgets/boardgame_expansions_section.dart';
import '../widgets/bgg_community_rating_panel.dart';
import '../models/boardgame_play_session.dart';
import '../widgets/boardgame/boardgame_item_bento_layout.dart';
import '../widgets/boardgame_detail_bento.dart';
import '../widgets/boardgame_rules_bento.dart';
import '../widgets/collapsible_section.dart';
import '../widgets/detail_bento_tile.dart';
import '../widgets/profile/pantheon_bento.dart';
import '../widgets/compact_whereabouts_dropdown.dart';
import '../widgets/discogs_market_value_card.dart';
import '../widgets/friend_ratings_panel.dart';
import '../widgets/item_aspect_ratings_section.dart';
import '../widgets/videogame_platform_picker.dart';
import '../widgets/restaurant_visits_panel.dart';
import '../widgets/temporary_loan_toggle.dart';
import '../widgets/cost_per_play_badge.dart';
import '../widgets/recommend_to_friend_button.dart';
import '../utils/wishlist_market_metadata.dart';
import '../services/boardgame_expansion_service.dart';
import '../utils/tech_warranty.dart';
import '../utils/boardgame_display.dart';
import '../utils/boardgame_collection_visibility.dart';
import '../utils/boardgame_expansion_flow.dart';
import '../utils/boardgame_expansions.dart';
import '../services/global_play_history_service.dart';
import '../services/player_alias_service.dart';
import '../services/collection_change_history_service.dart';
import '../utils/copy_friend_item.dart';
import '../utils/friend_item_overlap.dart';
import '../utils/whereabouts_apply.dart';
import '../utils/whereabouts_persistence.dart';
import '../utils/owned_quantity_index.dart';
import '../utils/item_copy_units.dart';
import '../widgets/item_condition_pill.dart';
import '../widgets/item_copy_units_panel.dart';
import '../widgets/item_market_value_panel.dart';
import '../utils/navigate_to_card_set.dart';
import '../utils/wishlist_promote.dart';
import '../utils/item_favorite.dart';
import '../utils/app_page_route.dart';
import '../utils/display_text.dart';
import '../widgets/add_item_options_dialog.dart';
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
  late final TextEditingController _merchantController;
  late final TextEditingController _soldToController;
  late final TextEditingController _soldPriceController;
  late final TextEditingController _tradedForController;
  late final TextEditingController _tradedWithController;

  ItemCondition? _condition;
  DateTime? _warrantyEnd;
  List<CollectionGroup> _groups = [];
  Set<String> _selectedGroupIds = {};
  Timer? _saveDebounce;
  Timer? _quantityDebounce;
  bool _saveInFlight = false;
  bool _saveQueued = false;
  String? _bggDescription;
  String? _bggLongDescription;
  bool _bggDescriptionLoading = false;
  int? _bggBestPlayers;
  double? _bggAvgRating;

  int _ownedDisplayQty = 0;
  String? _expandedBento;
  bool _marketPanelOpen = false;
  bool _bggDescExpanded = false;
  int? _expansionCatalogTotal;
  List<BggGalleryPhoto> _bggPhotos = const [];
  bool _bggPhotosLoading = false;
  List<String>? _pantheonIds;
  int _pantheonCap = 10;
  bool _pantheonReady = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _ownedDisplayQty =
        widget.ownedQuantity ?? (_item.isWishlist ? 0 : _item.quantity);
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
    _merchantController = TextEditingController(
      text: _item.metadata?['merchant']?.toString() ?? '',
    );
    _soldToController = TextEditingController(
      text: _item.metadata?['sold_to']?.toString() ?? '',
    );
    _soldPriceController = TextEditingController(
      text: _item.metadata?['sold_price']?.toString() ?? '',
    );
    _tradedForController = TextEditingController(
      text: _item.metadata?['traded_for']?.toString() ?? '',
    );
    _tradedWithController = TextEditingController(
      text: _item.metadata?['traded_with']?.toString() ?? '',
    );
    final rawWarranty = _item.metadata?['warranty_end']?.toString();
    if (rawWarranty != null && rawWarranty.isNotEmpty) {
      _warrantyEnd = DateTime.tryParse(rawWarranty);
    }
    _syncGroupSelectionFromItem();
    _loadBggDescription();
    _prefetchPantheon();
    _loadExpansionCatalogTotal();
    PlayerAliasService.instance.ensureLoaded();
    if (!widget.readOnly) {
      _reviewController.addListener(_scheduleSave);
      _priceController.addListener(_scheduleSave);
      _gamesPlayedController.addListener(_scheduleSave);
      _personalRulesController.addListener(_scheduleSave);
      _merchantController.addListener(_scheduleSave);
      _soldToController.addListener(_scheduleSave);
      _soldPriceController.addListener(_scheduleSave);
      _tradedForController.addListener(_scheduleSave);
      _tradedWithController.addListener(_scheduleSave);
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
          .select(
            'title, category, subcategory, metadata, quantity, is_wishlist, is_sold',
          )
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

  Future<void> _loadExpansionCatalogTotal() async {
    if (_item.category != CollectionCategory.boardgame) return;
    if (!BoardgameExpansionService.itemActsAsBase(_item)) return;
    final cached = _item.metadata?['bgg_expansion_total'];
    if (cached is num) {
      _expansionCatalogTotal = cached.round();
      return;
    }
    final bggId = _item.metadata?['bgg_id']?.toString();
    if (bggId == null || bggId.isEmpty) return;
    try {
      final list = await BggService.fetchExpansions(bggId);
      if (!mounted) return;
      setState(() => _expansionCatalogTotal = list.length);
      final meta = Map<String, dynamic>.from(_item.metadata ?? {});
      meta['bgg_expansion_total'] = list.length;
      _item = _item.copyWith(metadata: meta);
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

    final shortFromMeta = cleanBggText(meta?['bgg_short_description']?.toString());
    final longFromMeta = cleanBggText(meta?['bgg_description']?.toString());
    final galleryFromMeta = _bggGalleryUrls(meta);
    if (shortFromMeta.isNotEmpty || longFromMeta.isNotEmpty) {
      if (mounted) {
        setState(() {
          if (shortFromMeta.isNotEmpty) _bggDescription = shortFromMeta;
          if (longFromMeta.isNotEmpty) _bggLongDescription = longFromMeta;
        });
      }
    }
    final bggId = meta?['bgg_id']?.toString();
    if (bggId != null && bggId.isNotEmpty) {
      unawaited(_loadBggPhotos(bggId));
    }
    final needsLong = longFromMeta.isEmpty;
    if (!needsLong &&
        shortFromMeta.isNotEmpty &&
        bestFromMeta != null &&
        avgFromMeta != null &&
        galleryFromMeta.isNotEmpty) {
      return;
    }

    if (bggId == null || bggId.isEmpty) return;

    if (mounted && shortFromMeta.isEmpty && longFromMeta.isEmpty) {
      setState(() => _bggDescriptionLoading = true);
    }
    var details = await BggService.getGameFullDetails(bggId);
    if (details == null || !details.containsKey('bgg_designers')) {
      details = await BggService.fetchUncachedGameDetails(bggId) ?? details;
    }
    if (!mounted) return;
    final short = cleanBggText(details?['bgg_short_description']?.toString());
    final long = cleanBggText(details?['bgg_description']?.toString());
    setState(() {
      if (short.isNotEmpty) _bggDescription = short;
      if (long.isNotEmpty) _bggLongDescription = long;
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
      'bgg_description',
      'bgg_avg_rating',
      'bgg_best_players',
      'bgg_gallery_urls',
      'bgg_designers',
      'bgg_publishers',
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
    _soldToController.dispose();
    _soldPriceController.dispose();
    _tradedForController.dispose();
    _tradedWithController.dispose();
    _merchantController.dispose();
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
        if (_item.isWishlist) {
          unawaited(_resolveOwnedQuantity());
        } else {
          _ownedDisplayQty = _item.quantity.clamp(0, 9999);
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
      _item = _item.copyWith(groupId: first, groupName: _groupNameById(first));
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
    final minQ = 0;
    final next = (_item.quantity + delta).clamp(minQ, 9999);
    if (next == _item.quantity) return;
    setState(() => _item = _item.copyWith(quantity: next));
    _quantityDebounce?.cancel();
    _quantityDebounce = Timer(const Duration(milliseconds: 300), _saveNow);
  }

  Future<void> _pickWarrantyEnd() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _warrantyEnd ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 15),
      helpText: 'Fin de garantie',
    );
    if (picked == null || !mounted) return;
    setState(() => _warrantyEnd = picked);
    _scheduleSave();
  }

  void _clearWarrantyEnd() {
    setState(() => _warrantyEnd = null);
    _scheduleSave();
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    final gamesPlayed = int.tryParse(_gamesPlayedController.text.trim());

    var meta = Map<String, dynamic>.from(_item.metadata ?? {});
    if (_item.category == CollectionCategory.tech) {
      final merchant = _merchantController.text.trim();
      if (merchant.isEmpty) {
        meta.remove('merchant');
      } else {
        meta['merchant'] = merchant;
      }
      if (_warrantyEnd != null) {
        final d = _warrantyEnd!;
        meta['warranty_end'] =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      } else {
        meta.remove('warranty_end');
      }
    }
    void setOrClear(String key, String value) {
      final t = value.trim();
      if (t.isEmpty) {
        meta.remove(key);
      } else {
        meta[key] = t;
      }
    }

    setOrClear('sold_to', _soldToController.text);
    setOrClear('sold_price', _soldPriceController.text);
    setOrClear('traded_for', _tradedForController.text);
    setOrClear('traded_with', _tradedWithController.text);

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
      metadata: meta,
      isWishlist: _item.isWishlist,
      clearPurchasePrice: _priceController.text.trim().isEmpty,
      clearGamesPlayed: _gamesPlayedController.text.trim().isEmpty,
      clearGroup: groupIds.isEmpty,
    );

    try {
      final whereabouts = buildWhereaboutsDbFields(_item, groupIds: groupIds);
      final payload = _item.toUpdateJson();
      var meta = Map<String, dynamic>.from(_item.metadata ?? {});
      meta = mergeMetadataPreservingHolder(
        meta,
        Map<String, dynamic>.from(whereabouts['metadata'] as Map),
      );
      meta = finalizeMetadataPayload(_item, meta);
      payload['metadata'] = meta;
      payload['location_user_id'] = whereabouts['location_user_id'];
      payload['group_id'] = groupIds.isEmpty ? null : groupIds.first;
      await Supabase.instance.client
          .from('collection_items')
          .update(payload)
          .eq('id', _item.id);
      await _itemGroupService.syncItemGroupsWithItem(_item, groupIds);
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
    if (!_item.isWishlist) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AddItemOptionsDialog(
        itemTitle: cleanDisplayText(_item.title),
        itemImageUrl: _item.imageUrl,
        defaultWishlist: false,
        onConfirm: (options) async {
          try {
            await promoteWishlistToCollection(
              _item,
              locationUserId: options.locationUserId,
              holderLabel: options.holderLabel,
              groupId: options.groupId,
              quantity: options.quantity,
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '« ${cleanDisplayText(_item.title)} » est dans ta collection',
                ),
              ),
            );
            await _reloadItem();
            if (mounted && !_item.isWishlist && _ownedDisplayQty < 1) {
              setState(() => _ownedDisplayQty = 1);
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
            }
          }
        },
      ),
    );
  }

  Future<void> _toggleFavoriteFromMenu() async {
    try {
      final updated = await toggleItemFavorite(_item);
      if (mounted) setState(() => _item = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de mettre à jour le favori')),
        );
      }
    }
  }

  Future<void> _openShopSearch() async {
    final q = Uri.encodeComponent(
      '${cleanDisplayText(_item.title)} jeu société acheter',
    );
    final uri = Uri.parse('https://www.google.com/search?q=$q');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildWishlistPurchaseBlock(bool ro) {
    final avg = marketPriceAvgFromMetadata(_item.metadata);
    final second = marketSecondhandPriceFromMetadata(_item.metadata);
    final neu = marketNewPriceMinFromMetadata(_item.metadata);
    final estimate = avg ?? neu ?? second;
    final estimateLabel = estimate != null && estimate > 0
        ? '~${formatEuroChip(estimate, compact: false)}'
        : null;
    final priority = _item.isFavorite;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: ro ? null : _toggleFavoriteFromMenu,
          icon: Icon(
            priority ? Icons.favorite : Icons.favorite_border,
            color: Colors.redAccent,
          ),
          label: Text(
            priority
                ? '❤️ Priorité haute (Coup de cœur)'
                : 'Marquer en priorité / Coup de cœur',
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(
              color: priority ? Colors.redAccent : Colors.grey.shade400,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Budget / Prix cible',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  estimateLabel != null
                      ? 'Estimation marché : $estimateLabel'
                      : 'Pas encore d’estimation — cherche en boutique.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _priceController,
                  readOnly: ro,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Prix cible (€)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _scheduleSave(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _openShopSearch,
                    icon: const Icon(Icons.storefront_outlined, size: 18),
                    label: const Text('Chercher en boutique'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _promoteFromWishlist,
            icon: const Icon(Icons.check_circle),
            label: const Text(
              '✅ Je l\'ai reçu / acheté — Passer dans ma collection',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
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
        unawaited(
          CollectionChangeHistoryService.instance.recordLoan(
            item: updated,
            borrower: updated.loaneeDisplayName,
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Prêté à ${updated.loaneeDisplayName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  Future<void> _returnLoan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Objet rendu ?'),
        content: Text('Confirmer que « ${_item.title} » est de retour ?'),
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
        unawaited(
          CollectionChangeHistoryService.instance.recordReturn(item: updated),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Prêt clôturé')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
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

    await CollectionChangeHistoryService.instance.recordDeleted(_item);
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
    final isTech = _item.category == CollectionCategory.tech;
    final isVideogame = _item.category == CollectionCategory.videogame;
    final cardSetName = _item.metadata?['set_name']?.toString().trim();
    final canOpenSet =
        isCard &&
        _item.cardSubcategory?.hasSetBrowser == true &&
        (_item.metadata?['set_id']?.toString().trim().isNotEmpty ?? false);
    final ro = widget.readOnly;
    final isWishlist = _item.isWishlist;
    final ownedQty = _ownedDisplayQty;

    final expansionOf = boardgameExpansionOfLabel(_item);

    return Scaffold(
      appBar: AppAppBar(
        title: cleanDisplayText(_item.title),
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
            PopupMenuButton<_ItemMenuAction>(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) async {
                switch (action) {
                  case _ItemMenuAction.favorite:
                    await _toggleFavoriteFromMenu();
                  case _ItemMenuAction.pantheon:
                    await _offerPantheonSlot();
                  case _ItemMenuAction.recommend:
                    if (!mounted) return;
                    await RecommendToFriendButton.openFor(context, _item);
                  case _ItemMenuAction.location:
                    if (!mounted) return;
                    await _lend();
                  case _ItemMenuAction.delete:
                    await _delete();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: _ItemMenuAction.favorite,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _item.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: Colors.pinkAccent,
                    ),
                    title: Text(
                      isWishlist
                          ? (_item.isFavorite
                              ? 'Retirer la priorité'
                              : 'Priorité / Coup de cœur')
                          : (_item.isFavorite
                              ? 'Retirer des favoris'
                              : 'Ajouter aux favoris'),
                    ),
                  ),
                ),
                if (!isWishlist)
                  const PopupMenuItem(
                    value: _ItemMenuAction.pantheon,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.emoji_events_outlined),
                      title: Text('Ajouter au Panthéon'),
                    ),
                  ),
                if (Supabase.instance.client.auth.currentUser != null)
                  const PopupMenuItem(
                    value: _ItemMenuAction.recommend,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.chat_bubble_outline),
                      title: Text('Recommander à un ami'),
                    ),
                  ),
                if (!isWishlist)
                  const PopupMenuItem(
                    value: _ItemMenuAction.location,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.place_outlined),
                      title: Text('Localisation / Prêter'),
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _ItemMenuAction.delete,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
                    title: Text(
                      'Supprimer l\'objet',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (!isBoardgame)
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
                          ? Hero(
                              tag: collectionCoverHeroTag(_item.id),
                              child: SizedBox.expand(
                                child: CollectionCoverImage(
                                  url: _item.imageUrl!,
                                  height: 280,
                                  bookCover: isBook,
                                  boxedCover: isBook || isCard,
                                  largeSource: true,
                                  fit: BoxFit.contain,
                                ),
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
                child: BoardgameDetailWidthLimiter(
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isBoardgame) ...[
                      BoardgameDetailCompactHeader(
                        item: _item,
                        expansionOfLabel: expansionOf,
                        belowTitle: _bggShortHook(),
                      ),
                      if (_bggDescExpanded) _bggLongBody(),
                      const SizedBox(height: 16),
                    ],
                    if (!ro && isBoardgame && !_item.isWishlist)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _offerPantheonSlot,
                          icon: const Icon(Icons.emoji_events_outlined),
                          label: const Text('Ajouter au Panthéon'),
                        ),
                      ),
                    if (ro)
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.visibility,
                                color: Colors.blue.shade700,
                              ),
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
                    if (!isBoardgame) ...[
                      Text(
                        _item.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!ro &&
                        isBoardgame &&
                        _item.isExpansion &&
                        expansionOf != null) ...[
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
                                  final base =
                                      await promoteOrphanExpansionToBase(
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
                                label: const Text(
                                  'Ajouter / lier le jeu de base',
                                ),
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
                        color:
                            widget.friendOverlap ==
                                FriendOverlapKind.inCollection
                            ? Colors.green.shade50
                            : Colors.amber.shade50,
                        child: ListTile(
                          leading: Icon(
                            widget.friendOverlap ==
                                    FriendOverlapKind.inCollection
                                ? Icons.check_circle_outline
                                : Icons.favorite_border,
                            color:
                                widget.friendOverlap ==
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
                      _buildWishlistPurchaseBlock(ro),
                      const SizedBox(height: 16),
                    ],
                    if (!isBoardgame)
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
                    if (!isWishlist)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (_item.createdAtLabel != null ||
                                _item.addedByUsername != null)
                              Expanded(
                                child: Text(
                                  [
                                    if (_item.createdAtLabel != null)
                                      _item.createdAtLabel!,
                                    if (_item.addedByUsername != null)
                                      'Ajouté par ${_item.addedByUsername}',
                                  ].join(' · '),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            Flexible(
                              child: Text(
                                _ownedQtyLabel(ownedQty),
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (!ro) ...[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: _item.quantity > 0
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
                    if (!isWishlist && _groupOwnershipSubtitle().isNotEmpty)
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
                    if (isBoardgame) ...[
                      const SizedBox(height: 8),
                      _buildBggDescriptionSection(),
                    ],
                    const SizedBox(height: 16),
                    _buildInformationsSection(
                      isBoardgame: isBoardgame,
                      metadataRows: metadataRows,
                    ),
                    if (isBoardgame && !isWishlist) ...[
                      const SizedBox(height: 12),
                      DetailBentoTile(
                        icon: Icons.history_edu_outlined,
                        title: 'Parties et classements',
                        subtitle: _boardgameHistoriqueSubtitle(),
                        accent: Colors.orange.shade800,
                        expanded: _expandedBento == 'plays',
                        onTap: () => setState(
                          () => _expandedBento =
                              _expandedBento == 'plays' ? null : 'plays',
                        ),
                        child: BoardgamePlaySectionsPanel(
                          item: _item,
                          readOnly: ro,
                          onMetadataChanged: _onBoardgamePlaysMetadataChanged,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DetailBentoTile(
                        icon: Icons.star_outline,
                        title: 'Notes et avis',
                        subtitle: _boardgameNotesBentoSubtitle(),
                        accent: _item.category.color,
                        expanded: _expandedBento == 'rating',
                        onTap: () => setState(
                          () => _expandedBento =
                              _expandedBento == 'rating' ? null : 'rating',
                        ),
                        child: _buildNotesAndReviewsPanel(
                          ro,
                          showCommunityRating: true,
                        ),
                      ),
                      if (BoardgameExpansionService.itemActsAsBase(_item)) ...[
                        const SizedBox(height: 12),
                        DetailBentoTile(
                          icon: Icons.extension_outlined,
                          title: 'Extensions',
                          subtitle: _boardgameExtensionsSubtitle(),
                          accent: _item.category.color,
                          expanded: _expandedBento == 'extensions',
                          onTap: () => setState(
                            () => _expandedBento =
                                _expandedBento == 'extensions'
                                    ? null
                                    : 'extensions',
                          ),
                          child: BoardgameExpansionsSection(
                            item: _item,
                            readOnly: ro,
                            onItemUpdated: (updated) =>
                                setState(() => _item = updated),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DetailBentoTile(
                        icon: Icons.share_location_outlined,
                        title: 'Localisation et partages',
                        subtitle: _boardgameLocationShareSubtitle(),
                        accent: _item.category.color,
                        expanded: _expandedBento == 'share',
                        onTap: () => setState(
                          () => _expandedBento =
                              _expandedBento == 'share' ? null : 'share',
                        ),
                        child: _buildShareGroupsPanel(ro),
                      ),
                      const SizedBox(height: 12),
                      BoardgameRulesBento(
                        item: _item,
                        readOnly: ro,
                        expanded: _expandedBento == 'rules',
                        onToggle: () => setState(
                          () => _expandedBento =
                              _expandedBento == 'rules' ? null : 'rules',
                        ),
                        onPersonalRulesChanged: (encoded) {
                          _personalRulesController.text = encoded;
                          setState(() {
                            _item = _item.copyWith(
                              personalRules: encoded.isEmpty ? null : encoded,
                            );
                          });
                          _scheduleSave();
                        },
                      ),
                      const SizedBox(height: 12),
                      DetailBentoTile(
                        icon: Icons.payments_outlined,
                        title: 'Valeur',
                        subtitle: _boardgamePrixSubtitle(),
                        accent: _item.category.color,
                        expanded: _expandedBento == 'price',
                        onTap: () => setState(
                          () => _expandedBento =
                              _expandedBento == 'price' ? null : 'price',
                        ),
                        child: _buildBoardgamePrixObsPanel(ro),
                      ),
                      if (!ro && ownedQty > 0) ...[
                        const SizedBox(height: 12),
                        DetailBentoTile(
                          icon: Icons.sell_outlined,
                          title: 'Doubles et ventes',
                          subtitle: _saleDispositionSubtitle(
                            includeCopyCount: true,
                          ),
                          accent: _item.category.color,
                          expanded: _expandedBento == 'sale',
                          onTap: () => setState(
                            () => _expandedBento =
                                _expandedBento == 'sale' ? null : 'sale',
                          ),
                          child: _buildDoublesSalePanel(ro, isBoardgame),
                        ),
                      ],
                    ],
                    if (!isWishlist && !isBoardgame) ...[
                      const SizedBox(height: 12),
                      DetailBentoTile(
                        icon: Icons.group_outlined,
                        title: 'Partage & groupes',
                        subtitle: _shareGroupsSubtitle(),
                        accent: _item.category.color,
                        expanded: _expandedBento == 'share',
                        onTap: () => setState(
                          () => _expandedBento =
                              _expandedBento == 'share' ? null : 'share',
                        ),
                        child: _buildShareGroupsPanel(ro),
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
                                setState(
                                  () => _item = _item.copyWith(isRead: v),
                                );
                                _saveNow();
                              },
                      ),
                    ],
                    if (isVideogame && !_item.isSold) ...[
                      CollapsibleSection(
                        title: 'Jeu & progression',
                        accentColor: _item.category.color,
                        child: VideogameDetailSection(
                          metadata: _item.metadata,
                          readOnly: ro,
                          onMetadataChanged: (meta) {
                            setState(() => _item = _item.copyWith(metadata: meta));
                            _saveNow();
                          },
                        ),
                      ),
                    ],
                    if (!(isBoardgame && !isWishlist)) ...[
                      const SizedBox(height: 12),
                      DetailBentoTile(
                        icon: Icons.star_outline,
                        title: 'Ma note & avis',
                        subtitle: _ratingBentoSubtitle(),
                        accent: _item.category.color,
                        expanded: _expandedBento == 'rating',
                        onTap: () => setState(
                          () => _expandedBento =
                              _expandedBento == 'rating' ? null : 'rating',
                        ),
                        child: _buildNotesAndReviewsPanel(
                          ro,
                          showCommunityRating: isBoardgame,
                        ),
                      ),
                    ],
                    if (_item.category == CollectionCategory.media &&
                        !isWishlist) ...[
                      const SizedBox(height: 16),
                      DiscogsMarketValueCard(
                        releaseId: _item.metadata?['discogs_release_id']
                            ?.toString(),
                        artist: _item.metadata?['artist']?.toString(),
                        albumTitle: _item.title,
                      ),
                    ],
                    if (_item.category == CollectionCategory.restaurant &&
                        !ro) ...[
                      const Divider(height: 28),
                      RestaurantVisitsPanel(item: _item),
                    ],
                    if (!ro && !isWishlist && !_item.isGroupOwned) ...[
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
                              : 'Les objets vendus ne peuvent pas être prêtés.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                    if (!ro && !isWishlist && ownedQty > 0 && !isBoardgame) ...[
                      const SizedBox(height: 12),
                      DetailBentoTile(
                        icon: Icons.sell_outlined,
                        title: 'Doubles & vente',
                        subtitle: _saleDispositionSubtitle(),
                        accent: _item.category.color,
                        expanded: _expandedBento == 'sale',
                        onTap: () => setState(
                          () => _expandedBento =
                              _expandedBento == 'sale' ? null : 'sale',
                        ),
                        child: _buildDoublesSalePanel(ro, isBoardgame),
                      ),
                    ],
                    if ((!isWishlist || isTech) && !isBoardgame) ...[
                      const SizedBox(height: 12),
                      DetailBentoTile(
                        icon: Icons.payments_outlined,
                        title: isTech ? 'Budget & garantie' : 'Valeur & état',
                        subtitle: _valueConditionSubtitle(isTech: isTech),
                        accent: _item.category.color,
                        expanded: _expandedBento == 'value',
                        onTap: () => setState(
                          () => _expandedBento =
                              _expandedBento == 'value' ? null : 'value',
                        ),
                        child: Column(
                          children: [
                            if (isTech && _warrantyEnd != null) ...[
                              _buildWarrantyAlert(),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _priceController,
                              readOnly: ro,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: isTech
                                    ? 'Prix d\'achat (€)'
                                    : 'Prix d\'achat (€)',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            if (isTech) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _merchantController,
                                readOnly: ro,
                                decoration: const InputDecoration(
                                  labelText: 'Marchand',
                                  hintText: 'LDLC, Amazon, Fnac…',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Fin de garantie'),
                                subtitle: Text(
                                  _warrantyEnd == null
                                      ? 'Non renseignée'
                                      : warrantySubtitle(
                                              '${_warrantyEnd!.year}-${_warrantyEnd!.month.toString().padLeft(2, '0')}-${_warrantyEnd!.day.toString().padLeft(2, '0')}',
                                            ) ??
                                            'Date invalide',
                                ),
                                trailing: ro
                                    ? null
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_warrantyEnd != null)
                                            IconButton(
                                              tooltip: 'Effacer',
                                              onPressed: _clearWarrantyEnd,
                                              icon: const Icon(Icons.clear),
                                            ),
                                          IconButton(
                                            tooltip: 'Choisir une date',
                                            onPressed: _pickWarrantyEnd,
                                            icon: const Icon(Icons.event),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
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
              ),
            ]),
          ),
        ],
      ),
    );
  }

  String _boardgameHistoriqueSubtitle() {
    final sessions = parseBoardgamePlays(_item.metadata);
    if (sessions.isEmpty) return 'Aucune partie — lance un score';
    final last = sessions
        .map((s) => s.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final wins = <String, int>{};
    for (final s in sessions) {
      final w = s.effectiveWinner?.trim();
      if (w == null || w.isEmpty) continue;
      wins[w] = (wins[w] ?? 0) + 1;
    }
    String? dominant;
    var best = 0;
    for (final e in wins.entries) {
      if (e.value > best) {
        best = e.value;
        dominant = e.key;
      }
    }
    final date =
        '${last.day.toString().padLeft(2, '0')}/${last.month.toString().padLeft(2, '0')}/${last.year}';
    final n = sessions.length;
    final base = '$n partie${n > 1 ? 's' : ''} · Dernière partie le $date';
    if (dominant == null) return base;
    return '$base · Top 1 : $dominant';
  }

  String _boardgamePrixSubtitle() => _valueConditionSubtitle(isTech: false);

  void _onBoardgamePlaysMetadataChanged(Map<String, dynamic> meta) {
    final count = parseBoardgamePlays(meta).length;
    setState(() {
      _item = _item.copyWith(metadata: meta);
      _gamesPlayedController.text = count > 0 ? count.toString() : '';
    });
    _saveNow();
    unawaited(
      ActivityService().logPlayEdited(
        itemId: _item.id,
        ownerId: _item.addedBy,
        itemTitle: _item.title,
      ),
    );
  }

  Widget _buildBoardgamePrixObsPanel(bool ro) {
    final multi = itemUsesCopyUnits(_item);
    final second = marketSecondhandPriceFromMetadata(_item.metadata);
    final newMin = marketNewPriceMinFromMetadata(_item.metadata);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_item.isWishlist && !_item.isSold)
          CostPerPlayBadge(
            purchasePrice: _item.purchasePrice,
            estimatedValue: second ?? newMin,
            plays: parseBoardgamePlays(_item.metadata).length,
          ),
        const SizedBox(height: 12),
        DetailBentoSubTile(
          icon: Icons.query_stats_rounded,
          title: 'Estimations du marché',
          subtitle: second != null || newMin != null
              ? [
                  if (second != null) 'Occasion ≈ ${formatEuroChip(second, compact: false)}',
                  if (newMin != null) 'Neuf dès ${formatEuroChip(newMin, compact: false)}',
                ].join(' · ')
              : 'Prix neuf, occasion et boutiques',
          accent: Colors.teal,
          selected: _marketPanelOpen,
          onTap: () => setState(() => _marketPanelOpen = !_marketPanelOpen),
        ),
        if (_marketPanelOpen) ...[
          const SizedBox(height: 10),
          ItemMarketValuePanel(
            item: _item,
            readOnly: ro,
            onItemUpdated: (next) => setState(
              () => _item = _item.copyWith(metadata: next.metadata),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (multi)
          ItemCopyUnitsPanel(
            item: _item,
            groups: _groups,
            selectedGroupIds: _selectedGroupIds,
            readOnly: ro,
            mode: ItemCopyUnitsMode.value,
            onItemChanged: (next) {
              setState(() => _item = next);
              _saveNow();
            },
          )
        else ...[
          TextField(
            controller: _priceController,
            readOnly: ro,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
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
                (c) => DropdownMenuItem(value: c, child: Text(c.label)),
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
        const SizedBox(height: 16),
        TextField(
          controller: _personalRulesController,
          readOnly: ro,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Notes & observations',
            border: OutlineInputBorder(),
          ),
          onChanged: ro ? null : (_) => _scheduleSave(),
        ),
      ],
    );
  }

  Widget _buildShareGroupsPanel(bool ro) {
    final multi = itemUsesCopyUnits(_item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!ro && !multi)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                if (_groups.isEmpty) await _loadGroups();
                if (!mounted) return;
                if (_groups.isEmpty) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Crée d\'abord un groupe dans le menu « Groupes »',
                      ),
                    ),
                  );
                  return;
                }
                final picked = await _pickGroups(initial: _selectedGroupIds);
                if (!mounted || picked == null) return;
                if (picked.isEmpty) {
                  setState(() {
                    _selectedGroupIds = {};
                    _item = _item.copyWith(clearGroup: true);
                  });
                } else {
                  final first = picked.first;
                  final g = _groups.firstWhere((x) => x.id == first);
                  setState(() {
                    _selectedGroupIds = picked;
                    _item = _item.copyWith(
                      groupId: first,
                      groupName: g.name,
                      metadata: _metadataWithGroups(picked.toList()),
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
        if (_selectedGroupIds.isNotEmpty && !multi) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _groups
                .where((g) => _selectedGroupIds.contains(g.id))
                .map(
                  (g) => Chip(
                    label: Text(g.name),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        if (!multi) const SizedBox(height: 12),
        if (multi)
          ItemCopyUnitsPanel(
            item: _item,
            groups: _groups,
            selectedGroupIds: _selectedGroupIds,
            readOnly: ro,
            mode: ItemCopyUnitsMode.whereabouts,
            onItemChanged: (next) {
              setState(() {
                _item = next;
                _syncGroupSelectionFromItem();
              });
              _saveNow();
            },
          )
        else
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
              final fromLabel = _item.locationLabel?.trim().isNotEmpty == true
                  ? _item.locationLabel!
                  : (_item.locationUserId != null ? 'Chez quelqu\'un' : '—');
              final next = applyWhereaboutsChange(
                _item,
                locationUserId: locationUserId,
                holderLabel: holderLabel,
                clearHolder: clearHolder,
                manualHolder: manualHolder,
              );
              final toLabel = next.locationLabel?.trim().isNotEmpty == true
                  ? next.locationLabel!
                  : (next.locationUserId != null ? 'Chez quelqu\'un' : '—');
              setState(() => _item = next);
              if (manualHolder || locationUserId != null || clearHolder) {
                unawaited(
                  CollectionChangeHistoryService.instance.recordLocationChange(
                    item: next,
                    fromLabel: fromLabel,
                    toLabel: toLabel,
                  ),
                );
                _saveNow();
              }
            },
          ),
        if (!ro &&
            !multi &&
            isAwayFromHome(
              _item,
              meUserId: Supabase.instance.client.auth.currentUser?.id,
            )) ...[
          const SizedBox(height: 8),
          TemporaryLoanToggle(
            isLoan: _item.isOnLoan,
            loanedAt: _item.loanedAt,
            borrowerName: _item.loanedToName,
            onBorrowerChanged: (name) {
              setState(() {
                _item = _item.copyWith(
                  loanedToName: name.isEmpty ? null : name,
                );
              });
              _scheduleSave();
            },
            onChanged: (isLoan, date) {
              setState(() {
                _item = applyTemporaryLoan(
                  _item,
                  isLoan: isLoan,
                  loanedAt: date,
                  meUserId: Supabase.instance.client.auth.currentUser?.id,
                );
              });
              _saveNow();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildNotesAndReviewsPanel(
    bool ro, {
    required bool showCommunityRating,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ma note',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        PrecisionStarRatingBar(
          rating: personalRatingOnFive(
                _item.rating,
                metadata: _item.metadata,
              ) ??
              0,
          readOnly: ro,
          onChanged: (value) {
            final clamped =
                double.parse(value.clamp(0.0, 5.0).toStringAsFixed(1));
            final meta = Map<String, dynamic>.from(_item.metadata ?? {});
            meta['rating_scale'] = '5';
            setState(() {
              _item = _item.copyWith(
                rating: clamped <= 0 ? null : clamped,
                clearRating: clamped <= 0,
                metadata: meta,
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
        if (showCommunityRating) ...[
          const SizedBox(height: 16),
          BggCommunityRatingPanel(
            avgRating:
                _bggAvgRating ??
                parseBggAvgRating(_item.metadata?['bgg_avg_rating']),
            loading: _bggDescriptionLoading,
          ),
        ],
        if (!ro) ...[
          const SizedBox(height: 16),
          FriendRatingsPanel(item: _item),
        ],
      ],
    );
  }

  Widget _buildDoublesSalePanel(bool ro, bool isBoardgame) {
    final copies = itemUsesCopyUnits(_item) ? readCopyUnits(_item) : const <ItemCopyUnit>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (copies.length >= 2) ...[
          for (var i = 0; i < copies.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 16, color: Colors.teal.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      copies[i].defaultLabel(i + 1),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (copies[i].condition != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ItemConditionPill(condition: copies[i].condition),
                    ),
                  Text(
                    formatEuroChip(copies[i].purchasePrice, compact: false),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('À vendre'),
          subtitle: const Text('Apparaît dans l\'onglet « À vendre »'),
          value: _item.isForSale && !_item.isSold,
          onChanged: _item.isSold
              ? null
              : (v) {
                  setState(() {
                    _item = _item.copyWith(
                      isForSale: v,
                      isSold: false,
                      metadata: _dispositionMeta(
                        keep: !v,
                        sell: v,
                        trade: false,
                      ),
                    );
                  });
                  _saveNow();
                },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Envie d\'échanger'),
          value: _dispositionIsTrade && !_item.isSold,
          onChanged: _item.isSold
              ? null
              : (v) {
                  setState(() {
                    _item = _item.copyWith(
                      isForSale: v ? true : _item.isForSale,
                      metadata: _dispositionMeta(
                        keep: !v && !_item.isForSale,
                        sell: !v && _item.isForSale,
                        trade: v,
                      ),
                    );
                  });
                  _saveNow();
                },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Marquer comme vendu'),
          subtitle: const Text('Retire de la collection active'),
          value: _item.isSold,
          onChanged: (v) {
            setState(() {
              _item = _item.copyWith(
                isSold: v,
                isForSale: v ? false : _item.isForSale,
                metadata: _dispositionMeta(
                  keep: !v && !_item.isForSale,
                  sell: false,
                  trade: false,
                  sold: v,
                ),
              );
            });
            _saveNow();
          },
        ),
        if (_item.isSold) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _soldToController,
            readOnly: ro,
            decoration: const InputDecoration(
              labelText: 'Vendu à',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _scheduleSave(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _soldPriceController,
            readOnly: ro,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Prix de vente (€)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _scheduleSave(),
          ),
        ],
        if (_dispositionIsTrade && !_item.isSold) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _tradedForController,
            readOnly: ro,
            decoration: const InputDecoration(
              labelText: 'Échangé contre',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _scheduleSave(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tradedWithController,
            readOnly: ro,
            decoration: const InputDecoration(
              labelText: 'Avec',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _scheduleSave(),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            avatar: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('Accès Vinted'),
            onPressed: () => _openVintedSearch(
              isBoardgame: isBoardgame,
              isMedia: _item.category == CollectionCategory.media,
            ),
          ),
        ),
      ],
    );
  }

  String _boardgameExtensionsSubtitle() {
    final owned = ownedExpansionCount(_item);
    final total = _expansionCatalogTotal;
    if (total != null && total > 0) {
      return '$owned / $total possédées';
    }
    if (owned <= 0) return '0 possédée';
    return '$owned possédée${owned > 1 ? 's' : ''}';
  }

  String _ownedQtyLabel(int ownedQty) {
    if (_item.isWishlist) {
      final info = OwnedCatalogIndex.lookup(_item);
      if (info != null && info.count > 0) return info.detailLabel;
      if (ownedQty > 0) return 'Possédé : $ownedQty';
      return 'Possédé : 0';
    }
    return 'Possédé : $ownedQty';
  }

  String _boardgameNotesBentoSubtitle() {
    final parts = <String>[];
    final perso = personalRatingOnFive(
      _item.rating,
      metadata: _item.metadata,
    );
    if (perso != null && perso > 0) {
      parts.add('Perso ${perso.toStringAsFixed(1)}/5');
    }
    final onFive = bggRatingOnFive(
      _bggAvgRating ?? _item.metadata?['bgg_avg_rating'],
    );
    if (onFive != null) {
      parts.add('Commu ${onFive.toStringAsFixed(1)}/5');
    }
    if (parts.isEmpty) return 'Perso — · Commu —';
    return parts.join(' · ');
  }

  String _boardgameLocationShareSubtitle() {
    final me = Supabase.instance.client.auth.currentUser;
    final loc = quickWhereaboutsSummaryLabel(
      _item,
      meUserId: me?.id,
      meDisplayName: me?.userMetadata?['display_name']?.toString(),
    );
    final groupNames = _groups
        .where((g) => _selectedGroupIds.contains(g.id))
        .map((g) => g.name)
        .toList();
    if (groupNames.isEmpty) return loc;
    return '$loc · partagé avec ${groupNames.join(', ')}';
  }

  Future<void> _prefetchPantheon() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final cap = (prefs.getInt('pantheon_cap:$uid') ?? 10).clamp(10, 20);
    List<String> ids = const [];
    try {
      final remote = await ProfileService().fetchPantheonIds(uid);
      if (remote != null) {
        ids = remote;
      } else {
        final raw = prefs.getString('pantheon:$uid');
        if (raw != null) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            ids = decoded.map((e) => e.toString()).where((id) => id.isNotEmpty).toList();
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pantheonIds = ids;
      _pantheonCap = cap;
      _pantheonReady = true;
    });
  }

  Future<void> _loadBggPhotos(String bggId) async {
    if (mounted) setState(() => _bggPhotosLoading = true);
    final photos = await BggService.fetchCommunityGallery(bggId);
    if (!mounted) return;
    setState(() {
      _bggPhotos = photos;
      _bggPhotosLoading = false;
    });
  }

  Future<Map<String, (String, String?)>> _pantheonFaces(List<String> ids) async {
    final wanted = ids.where((id) => id.isNotEmpty).toList();
    if (wanted.isEmpty) return {};
    try {
      final rows = await Supabase.instance.client
          .from('collection_items')
          .select('id, title, image_url')
          .inFilter('id', wanted);
      final out = <String, (String, String?)>{};
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id']?.toString();
        if (id == null) continue;
        final image = map['image_url']?.toString();
        out[id] = (
          map['title']?.toString() ?? 'Sans titre',
          image != null && image.isNotEmpty ? image : null,
        );
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _offerPantheonSlot() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    if (!_pantheonReady) await _prefetchPantheon();
    if (!mounted) return;
    final current = List<String>.from(_pantheonIds ?? const []);
    const cap = 20;
    final filled = current.where((id) => id.isNotEmpty).length;
    final shown = filled < 10 ? 10 : (filled >= cap ? cap : filled + 1);
    final faces = await _pantheonFaces(current);
    if (!mounted) return;
    final already = current.indexOf(_item.id);
    final slot = await showPantheonPlacePicker(
      context,
      alreadyAt: already >= 0 ? already + 1 : null,
      places: [
        for (var i = 0; i < shown; i++)
          PantheonPlaceOption(
            index: i,
            itemId: i < current.length ? current[i] : null,
            title: i < current.length ? faces[current[i]]?.$1 : null,
            imageUrl: i < current.length ? faces[current[i]]?.$2 : null,
          ),
      ],
    );
    if (slot == null || !mounted) return;
    final titleKey = _item.title.trim().toLowerCase();
    final alsoRemove = <String>{
      for (final entry in faces.entries)
        if ((entry.value.$1).trim().toLowerCase() == titleKey) entry.key,
    };
    final next = placeInPantheon(
      current,
      _item.id,
      targetIndex: slot,
      cap: cap,
      alsoRemove: alsoRemove,
    );
    await _persistPantheon(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Panthéon mis à jour')),
    );
  }

  Future<void> _persistPantheon(List<String> ids) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final unique = <String>[];
    for (final id in ids) {
      if (id.isEmpty || unique.contains(id)) continue;
      unique.add(id);
      if (unique.length >= 20) break;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pantheon:$uid', jsonEncode(unique));
    await prefs.setInt('pantheon_cap:$uid', _pantheonCap);
    if (mounted) setState(() => _pantheonIds = unique);
    PantheonMemory.instance.publish(uid, unique);
    try {
      await ProfileService().savePantheonIds(unique);
    } catch (_) {}
  }

  Widget _buildBggDescriptionSection() {
    if (_bggDescriptionLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final bggId = _item.metadata?['bgg_id']?.toString();
    if (_bggPhotos.isEmpty &&
        !_bggPhotosLoading &&
        (bggId == null || bggId.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Aperçus & matériel du jeu',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_bggPhotosLoading && _bggPhotos.isEmpty)
          const LinearProgressIndicator(minHeight: 2)
        else
          BggPhotoStrip(photos: _bggPhotos),
      ],
    );
  }

  String? get _bggHookText {
    final short = _bggDescription?.trim();
    if (short != null && short.isNotEmpty) return short;
    final long = _bggLongDescription?.trim();
    if (long == null || long.isEmpty) return null;
    final end = RegExp(r'[.!?]').firstMatch(long)?.start ?? -1;
    if (end <= 0 || end > 180) {
      return long.length > 140 ? long.substring(0, 140).trim() : long;
    }
    return long.substring(0, end + 1).trim();
  }

  Widget _bggShortHook() {
    final hook = _bggHookText;
    if (hook == null || hook.isEmpty) {
      if (!_bggDescriptionLoading) return const SizedBox.shrink();
      return const LinearProgressIndicator(minHeight: 2);
    }
    final long = _bggLongDescription?.trim() ?? '';
    final canToggle = long.isNotEmpty && long != hook;
    final style = GoogleFonts.lora(
      fontSize: 14,
      height: 1.4,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canToggle
          ? () => setState(() => _bggDescExpanded = !_bggDescExpanded)
          : null,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: hook),
            if (canToggle && !_bggDescExpanded)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Text(
                  '  + Voir plus',
                  style: style.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bggLongBody() {
    final hook = _bggHookText ?? '';
    var long = _bggLongDescription?.trim() ?? '';
    if (long.startsWith(hook)) {
      long = long.substring(hook.length).trim();
    }
    if (long.isEmpty) return const SizedBox.shrink();
    final style = GoogleFonts.lora(
      fontSize: 15,
      height: 1.55,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _bggDescExpanded = false),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(long, style: style),
            Text(
              '− Voir moins',
              style: style.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _creditLine(dynamic raw) {
    if (raw is List) {
      final text = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(', ');
      return text.isEmpty ? null : text;
    }
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }

  List<String> _bggGalleryUrls(Map<String, dynamic>? metadata) {
    final raw = metadata?['bgg_gallery_urls'];
    final urls = raw is List
        ? raw
              .map((url) => url.toString().trim())
              .where((url) => Uri.tryParse(url)?.hasScheme == true)
              .toSet()
              .toList()
        : <String>[];
    if (urls.isEmpty) {
      final cover = _item.imageUrl?.trim();
      if (cover != null &&
          cover.isNotEmpty &&
          Uri.tryParse(cover)?.hasScheme == true) {
        urls.add(cover);
      }
    }
    return urls;
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
    final designers = _creditLine(m['bgg_designers']);
    final publishers = _creditLine(m['bgg_publishers']);
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
        designers == null &&
        publishers == null &&
        bggPageUrl == null) {
      return const SizedBox.shrink();
    }

    final boardTiles = <Widget>[];
    if (isBoardgame) {
      if (players != null) {
        boardTiles.add(
          _infoTile(Icons.people, players, boardAccent, bestPlayersLabel),
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
        if (designers != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Créateur · $designers'),
          ),
        if (publishers != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Maison d\'édition · $publishers'),
          ),
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
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            subtitle: Text(
              row.value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
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

  Widget _buildWarrantyAlert() {
    if (_warrantyEnd == null) return const SizedBox.shrink();
    final iso =
        '${_warrantyEnd!.year}-${_warrantyEnd!.month.toString().padLeft(2, '0')}-${_warrantyEnd!.day.toString().padLeft(2, '0')}';
    final status = warrantyStatus(iso);
    if (status == TechWarrantyStatus.valid ||
        status == TechWarrantyStatus.unknown) {
      return const SizedBox.shrink();
    }
    final color = warrantyAccentColor(status);
    final message = warrantySubtitle(iso) ?? 'Garantie';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(
            status == TechWarrantyStatus.expired
                ? Icons.warning_amber_rounded
                : Icons.schedule_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _dispositionIsTrade =>
      _item.metadata?['disposition']?.toString() == 'trade';

  Map<String, dynamic> _dispositionMeta({
    bool keep = false,
    bool sell = false,
    bool trade = false,
    bool sold = false,
  }) {
    final meta = Map<String, dynamic>.from(_item.metadata ?? {});
    if (sold) {
      meta['disposition'] = 'sold';
    } else if (trade) {
      meta['disposition'] = 'trade';
    } else if (sell) {
      meta['disposition'] = 'sell';
    } else if (keep) {
      meta['disposition'] = 'keep';
    } else {
      meta.remove('disposition');
    }
    return meta;
  }

  String _shareGroupsSubtitle() {
    final parts = <String>[];
    final loc = _item.locationLabel?.trim();
    if (loc != null && loc.isNotEmpty) {
      parts.add(loc);
    }
    final groupNames = _groups
        .where((g) => _selectedGroupIds.contains(g.id))
        .map((g) => g.name)
        .toList();
    if (groupNames.isNotEmpty) {
      parts.add(groupNames.take(2).join(', '));
    } else if (_selectedGroupIds.isNotEmpty) {
      parts.add(
        '${_selectedGroupIds.length} groupe'
        '${_selectedGroupIds.length > 1 ? 's' : ''}',
      );
    }
    if (parts.isEmpty) return 'Chez moi · aucun groupe';
    return parts.join(' · ');
  }

  String _ratingBentoSubtitle() {
    final parts = <String>[];
    final perso = personalRatingOnFive(
      _item.rating,
      metadata: _item.metadata,
    );
    if (perso != null && perso > 0) {
      parts.add('Perso ${perso.toStringAsFixed(1)}/5');
    } else {
      parts.add('Perso —');
    }
    final onFive = bggRatingOnFive(
      _bggAvgRating ?? _item.metadata?['bgg_avg_rating'],
    );
    if (onFive != null) {
      parts.add('Commu ${onFive.toStringAsFixed(1)}/5');
    } else {
      parts.add('Commu —');
    }
    return parts.join(' · ');
  }

  String _saleDispositionSubtitle({bool includeCopyCount = false}) {
    final qty = _item.quantity;
    if (includeCopyCount && qty > 1) {
      final base = _saleDispositionSubtitleCore();
      return '$qty exemplaires · $base';
    }
    return _saleDispositionSubtitleCore();
  }

  String _saleDispositionSubtitleCore() {
    if (_item.isSold) {
      final to = _item.metadata?['sold_to']?.toString().trim();
      final price = _item.metadata?['sold_price']?.toString().trim();
      if (to != null && to.isNotEmpty && price != null && price.isNotEmpty) {
        return 'Vendu à $to · $price €';
      }
      if (to != null && to.isNotEmpty) return 'Vendu à $to';
      return 'Vendu';
    }
    if (_dispositionIsTrade) {
      final against = _item.metadata?['traded_for']?.toString().trim();
      final withWho = _item.metadata?['traded_with']?.toString().trim();
      if (against != null &&
          against.isNotEmpty &&
          withWho != null &&
          withWho.isNotEmpty) {
        return 'Échange : $against avec $withWho';
      }
      return 'Envie d\'échanger';
    }
    if (_item.isForSale) return 'Envie de vendre';
    return 'Dans ma collection';
  }

  String _valueConditionSubtitle({required bool isTech}) {
    final parts = <String>[];
    final price = _priceController.text.trim();
    if (price.isNotEmpty) parts.add('$price €');
    final cond = _condition?.label;
    if (cond != null && cond.isNotEmpty) parts.add(cond);
    if (isTech && _warrantyEnd != null) parts.add('Garantie');
    if (parts.isEmpty) return 'Non renseigné';
    return parts.join(' · ');
  }

  Future<void> _openVintedSearch({
    required bool isBoardgame,
    required bool isMedia,
  }) async {
    final title = _item.title.trim();
    // catalog[]=4881 = « Jeux de société » sur Vinted FR.
    final params = <String, String>{
      'search_text': isBoardgame ? title : title,
      'order': 'relevance',
      if (isBoardgame) 'catalog[]': '4881',
    };
    final uri = Uri.https('www.vinted.fr', '/catalog', params);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _ItemMenuAction { favorite, pantheon, recommend, location, delete }
