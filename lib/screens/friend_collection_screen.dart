import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/friend_service.dart';
import '../services/household_service.dart';
import '../services/profile_service.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_grid_layout.dart';
import '../navigation/app_navigation.dart';
import '../utils/copy_friend_item.dart';
import '../utils/friend_item_overlap.dart';
import '../utils/active_categories.dart';
import '../utils/holder_label_utils.dart';
import '../utils/pantheon_ranking.dart';
import '../widgets/collection_item_tile.dart';
import '../widgets/profile/own_profile_panel.dart';
import '../widgets/profile/pantheon_bento.dart';
import '../widgets/profile_avatar.dart';
import 'item_detail_screen.dart';

enum _ProfileScope { shared, atHome, added }

/// Collection et wishlist d'un ami (lecture seule).
class FriendCollectionScreen extends StatefulWidget {
  final String profileId;
  final String username;
  final String? avatarUrl;
  final String? accentColor;
  final bool shareCollections;

  const FriendCollectionScreen({
    super.key,
    required this.profileId,
    required this.username,
    this.avatarUrl,
    this.accentColor,
    required this.shareCollections,
  });

  @override
  State<FriendCollectionScreen> createState() => _FriendCollectionScreenState();
}

class _FriendCollectionScreenState extends State<FriendCollectionScreen> {
  final _friendService = FriendService();
  List<CollectionItem> _collectionItems = [];
  List<CollectionItem> _groupItems = [];
  List<CollectionItem> _wishlistItems = [];
  bool? _wishlistShared;
  bool _loading = true;
  String? _error;
  CollectionCategory _selectedCategory = CollectionCategory.boardgame;
  FriendOverlapIndex? _overlap;
  bool _categorySynced = false;
  _ProfileScope _scope = _ProfileScope.shared;
  List<String> _pantheonIds = [];
  int _pantheonCap = 10;
  bool _pantheonConfigured = false;
  bool _mine = false;
  Set<CollectionCategory> _activeCategories = CollectionCategory.defaultActive;

  @override
  void initState() {
    super.initState();
    _mine = Supabase.instance.client.auth.currentUser?.id == widget.profileId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (!widget.shareCollections && !_mine) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Collections non partagées. Active « Collections partagées » '
              'dans le menu de cet ami.';
        });
      }
      return;
    }

    try {
      await HouseholdService.instance.ensureLoaded();
      _collectionItems = await _friendService.fetchFriendCollectionItems(
        widget.profileId,
      );
      _groupItems = await _friendService.fetchItemsInMyGroups();
      _wishlistShared = await _friendService.canViewFriendWishlist(
        widget.profileId,
      );
      if (_wishlistShared == true) {
        _wishlistItems = await _friendService.fetchFriendWishlistItems(
          widget.profileId,
        );
      } else {
        _wishlistItems = [];
      }
      _overlap = await buildFriendOverlapIndex([
        ..._sharedItems(),
        ..._wishlistItems,
      ]);
      _activeCategories = await ActiveCategories.load();
      await _loadPantheon();
      _categorySynced = false;
    } catch (e) {
      _collectionItems = [];
      _wishlistItems = [];
      _overlap = null;
      _error = e.toString();
    }

    if (mounted) {
      setState(() => _loading = false);
      _pickInitialCategory([..._collectionItems, ..._wishlistItems]);
    }
  }

  void _pickInitialCategory(List<CollectionItem> items) {
    if (_categorySynced || items.isEmpty) return;
    if (items.any((i) => i.category == _selectedCategory)) {
      _categorySynced = true;
      return;
    }
    for (final cat in CollectionCategory.values) {
      if (items.any((i) => i.category == cat)) {
        _categorySynced = true;
        setState(() => _selectedCategory = cat);
        return;
      }
    }
  }

  Widget? _overlapBanner() {
    final o = _overlap;
    if (o == null || (o.inCollectionCount == 0 && o.inWishlistCount == 0)) {
      return null;
    }
    final parts = <String>[];
    if (o.inCollectionCount > 0) {
      parts.add(
        '${o.inCollectionCount} en commun',
      );
    }
    if (o.inWishlistCount > 0) {
      parts.add('${o.inWishlistCount} dans ta wishlist');
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, color: Colors.teal.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.teal.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<CollectionItem> _sharedItems() {
    final byId = <String, CollectionItem>{};
    for (final item in [..._collectionItems, ..._groupItems]) {
      byId[item.id] = item;
    }
    return byId.values.toList();
  }

  bool _isAtThisPerson(CollectionItem item) {
    if (item.locationUserId == widget.profileId) return true;
    final who = widget.username.trim().toLowerCase();
    final labels = <String>[
      if (item.locationLabel != null) item.locationLabel!,
      item.metadata?['holder_label']?.toString() ?? '',
    ];
    for (final raw in labels) {
      if (raw.trim().isEmpty) continue;
      if (holderLabelStorageValue(raw).trim().toLowerCase() == who) {
        return true;
      }
      final home = HouseholdService.instance.matchLabel(raw);
      if (home != null &&
          home.people.any((p) => p.trim().toLowerCase() == who)) {
        return true;
      }
    }
    return false;
  }

  List<CollectionItem> _itemsForScope() {
    switch (_scope) {
      case _ProfileScope.shared:
        return _sharedItems();
      case _ProfileScope.atHome:
        return _sharedItems().where(_isAtThisPerson).toList();
      case _ProfileScope.added:
        return [
          ..._sharedItems().where((i) => i.addedBy == widget.profileId),
          if (_wishlistShared != false) ..._wishlistItems,
        ];
    }
  }

  int _countFor(CollectionCategory category) =>
      _itemsForScope().where((i) => i.category == category).length;

  List<CollectionItem> _pantheonItems() {
    if (!_pantheonConfigured) return const [];
    final games = _sharedItems()
        .where((i) => i.category == CollectionCategory.boardgame && !i.isWishlist)
        .toList();
    final byId = {for (final g in games) g.id: g};
    final picked = <CollectionItem>[];
    final seen = <String>{};
    for (final id in _pantheonIds) {
      final item = byId[id];
      if (item == null || item.isExpansion) continue;
      final bgg = item.metadata?['bgg_id']?.toString().trim();
      final key = (bgg != null && bgg.isNotEmpty)
          ? 'bgg:$bgg'
          : 'title:${item.title.trim().toLowerCase()}';
      if (!seen.add(key)) continue;
      picked.add(item);
    }
    return picked.take(10).toList();
  }

  List<PantheonCandidate> _pantheonCandidates() {
    return [
      for (final item in _sharedItems())
        if (item.category == CollectionCategory.boardgame)
          PantheonCandidate(
            id: item.id,
            title: item.title,
            bggId: item.metadata?['bgg_id']?.toString(),
            isExpansion: item.isExpansion,
            isWishlist: item.isWishlist,
            rating: item.rating ?? 0,
          ),
    ];
  }

  Future<void> _loadPantheon() async {
    final prefs = await SharedPreferences.getInstance();
    final cap = prefs.getInt('pantheon_cap:${widget.profileId}');
    if (cap != null && mounted) _pantheonCap = cap.clamp(10, 20);
    final remote = await ProfileService().fetchPantheonIds(widget.profileId);
    if (remote != null) {
      _pantheonIds = remote;
      _pantheonConfigured = remote.isNotEmpty;
      return;
    }
    final raw = prefs.getString('pantheon:${widget.profileId}');
    if (raw == null) return;
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      _pantheonIds = decoded.map((e) => e.toString()).where((id) => id.isNotEmpty).toList();
      _pantheonConfigured = _pantheonIds.isNotEmpty;
    }
  }

  Future<void> _savePantheon(List<String> ids) async {
    if (!_mine) return;
    final unique = <String>[];
    for (final id in ids) {
      if (id.isEmpty || unique.contains(id)) continue;
      unique.add(id);
      if (unique.length == _pantheonCap) break;
    }
    try {
      await ProfileService().savePantheonIds(unique);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pantheon_cap:${widget.profileId}', _pantheonCap);
    await prefs.setString('pantheon:${widget.profileId}', jsonEncode(unique));
    if (mounted) {
      setState(() {
        _pantheonIds = unique;
        _pantheonConfigured = unique.isNotEmpty;
      });
    }
  }

  Future<void> _editPantheonSlot(int index) async {
    final seen = <String>{};
    final games = <CollectionItem>[];
    for (final item in _sharedItems()) {
      if (item.category != CollectionCategory.boardgame ||
          item.isWishlist ||
          item.isExpansion) {
        continue;
      }
      final bgg = item.metadata?['bgg_id']?.toString().trim();
      final key = (bgg != null && bgg.isNotEmpty)
          ? 'bgg:$bgg'
          : 'title:${item.title.trim().toLowerCase()}';
      if (!seen.add(key)) continue;
      games.add(item);
    }
    games.sort((a, b) => a.title.compareTo(b.title));
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Place #${index + 1}'),
        children: [
          for (final game in games.take(40))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, game.id),
              child: Text(game.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final next = [..._pantheonIds];
    while (next.length <= index) {
      next.add('');
    }
    next[index] = picked;
    await _savePantheon(next.where((id) => id.isNotEmpty).toList());
  }

  @override
  Widget build(BuildContext context) {
    final accent = ProfileAvatar.colorFromHex(widget.accentColor);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ProfileAvatar(
              avatarUrl: widget.avatarUrl,
              accentColorHex: widget.accentColor,
              fallbackInitial: widget.username,
              radius: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.username),
                  const Text(
                    'Profil',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Appui long sur un objet pour l\'ajouter chez toi',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Appui long sur une vignette → ajouter à ta collection ou wishlist',
                  ),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.grid_view_rounded),
            tooltip: 'Collections',
            onPressed: () => AppNavigation.openCollections(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildProfile(),
    );
  }

  Widget _buildProfile() {
    final shared = _sharedItems();
    final atHome = shared.where(_isAtThisPerson).length;
    final overlapBanner = _overlapBanner();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (_mine) const OwnProfilePanel(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _stat('${shared.length} jeux & objets'),
                  _stat('$atHome chez ${widget.username}'),
                  _stat('${_wishlistItems.length} en wishlist'),
                ],
              ),
              if (_mine || _pantheonConfigured) ...[
                const SizedBox(height: 12),
                PantheonBento(
                  ranked: _pantheonItems(),
                  editable: _mine,
                  slotCount: _pantheonCap,
                  onAutoFill: _mine
                      ? () => _savePantheon(
                            pickAutoPantheonIds(_pantheonCandidates()),
                          )
                      : null,
                  onExtend: _mine && _pantheonCap < 20
                      ? () async {
                          setState(() => _pantheonCap = 20);
                          await _savePantheon(_pantheonIds);
                        }
                      : null,
                  onEditSlot: _mine ? _editPantheonSlot : null,
                  onRemove: _mine
                      ? (index) {
                          final next = [..._pantheonIds];
                          if (index < next.length) next.removeAt(index);
                          _savePantheon(next);
                        }
                      : null,
                  onReorder: _mine
                      ? (oldIndex, newIndex) {
                          final next = [..._pantheonIds];
                          if (oldIndex >= next.length) return;
                          final id = next.removeAt(oldIndex);
                          final at = newIndex.clamp(0, next.length);
                          next.insert(at, id);
                          _savePantheon(next);
                        }
                      : null,
                ),
              ],
              if (overlapBanner != null) ...[
                const SizedBox(height: 8),
                overlapBanner,
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Collection & Groupes communs'),
                    selected: _scope == _ProfileScope.shared,
                    onSelected: (_) =>
                        setState(() => _scope = _ProfileScope.shared),
                  ),
                  ChoiceChip(
                    label: Text('📍 Actuellement chez ${widget.username}'),
                    selected: _scope == _ProfileScope.atHome,
                    onSelected: (_) =>
                        setState(() => _scope = _ProfileScope.atHome),
                  ),
                  ChoiceChip(
                    label: Text('Ajoutés par ${widget.username}'),
                    selected: _scope == _ProfileScope.added,
                    onSelected: (_) =>
                        setState(() => _scope = _ProfileScope.added),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _visibleCategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final cat = _visibleCategories[index];
                    final count = _countFor(cat);
                    final selected = cat == _selectedCategory;
                    return FilterChip(
                      label: Text(
                        count > 0 ? '${cat.label} ($count)' : cat.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: selected,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = cat),
                      avatar: Icon(cat.icon, size: 16),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
        _buildCategoryGridSliver(_selectedCategory),
      ],
    );
  }

  List<CollectionCategory> get _visibleCategories => CollectionCategory.values
      .where((c) => _activeCategories.contains(c))
      .toList();

  Widget _stat(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildCategoryGridSliver(CollectionCategory category) {
    final items =
        _itemsForScope().where((i) => i.category == category).toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Text(
            'Rien dans cette catégorie.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final grouped = CollectionGridGrouper.group(items);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      sliver: SliverGrid(
        gridDelegate:
            CollectionGridLayout.collectionDelegate(context, category),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = grouped[index];
            final item = entry.item;
            final overlap = _overlap?.kindFor(item);
            final shownOverlap = overlap == FriendOverlapKind.inCollection
                ? null
                : overlap;

            return CollectionItemTile(
              item: item,
              category: category,
              totalQuantity: entry.totalQuantity,
              showDuplicateBadge: entry.hasDuplicates,
              overlapKind: shownOverlap,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ItemDetailScreen(
                    item: item.copyWith(quantity: entry.totalQuantity),
                    readOnly: !_mine,
                    friendUsername: widget.username,
                    friendOverlap: overlap,
                  ),
                ),
              ),
              onLongPress: _mine
                  ? null
                  : () => showCopyFriendItemSheet(
                context,
                source: item,
                friendUsername: widget.username,
              ),
            );
          },
          childCount: grouped.length,
        ),
      ),
    );
  }
}
