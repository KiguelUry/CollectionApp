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
import '../navigation/app_route_observer.dart';
import '../services/pantheon_memory.dart';
import '../utils/copy_friend_item.dart';
import '../utils/friend_item_overlap.dart';
import '../utils/active_categories.dart';
import '../utils/holder_label_utils.dart';
import '../utils/hub_owned_count.dart';
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
  final bool collectionView;

  const FriendCollectionScreen({
    super.key,
    required this.profileId,
    required this.username,
    this.avatarUrl,
    this.accentColor,
    this.collectionView = false,
    required this.shareCollections,
  });

  @override
  State<FriendCollectionScreen> createState() => _FriendCollectionScreenState();
}

class _FriendCollectionScreenState extends State<FriendCollectionScreen>
    with RouteAware {
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
    final cached = _ProfileSessionCache.of(widget.profileId);
    if (cached != null) {
      _collectionItems = cached.collection;
      _groupItems = cached.groups;
      _wishlistItems = cached.wishlist;
      _wishlistShared = cached.wishlistShared;
      _pantheonIds = List<String>.from(cached.pantheonIds);
      _pantheonConfigured = cached.pantheonIds.isNotEmpty;
      _activeCategories = cached.active;
      _loading = false;
    }
    final memory = PantheonMemory.instance.idsFor(widget.profileId);
    if (memory != null) {
      _pantheonIds = memory;
      _pantheonConfigured = memory.isNotEmpty;
      if (cached == null) {
        _loading = _collectionItems.isEmpty && _pantheonIds.isEmpty;
      }
    }
    PantheonMemory.instance.addListener(_onPantheonMemory);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.unsubscribe(this);
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    PantheonMemory.instance.removeListener(_onPantheonMemory);
    super.dispose();
  }

  @override
  void didPopNext() {
    final memory = PantheonMemory.instance.idsFor(widget.profileId);
    if (memory != null && mounted) {
      setState(() {
        _pantheonIds = memory;
        _pantheonConfigured = memory.isNotEmpty;
      });
    }
    _load(silent: true);
  }

  void _onPantheonMemory() {
    final memory = PantheonMemory.instance.idsFor(widget.profileId);
    if (memory == null || !mounted) return;
    setState(() {
      _pantheonIds = memory;
      _pantheonConfigured = memory.isNotEmpty;
    });
  }

  Future<void> _load({bool silent = false}) async {
    final keepShown = silent || _collectionItems.isNotEmpty || _pantheonIds.isNotEmpty;
    if (!keepShown) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

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
      if (!keepShown) {
        _collectionItems = [];
        _wishlistItems = [];
        _overlap = null;
        _error = e.toString();
      }
    }

    if (mounted) {
      if (_error == null) {
        _ProfileSessionCache.save(
          widget.profileId,
          collection: _collectionItems,
          groups: _groupItems,
          wishlist: _wishlistItems,
          wishlistShared: _wishlistShared,
          pantheonIds: _pantheonIds,
          active: _activeCategories,
        );
      }
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
    if (_mine) return null;
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

  int _countFor(CollectionCategory category) => _itemsForScope()
      .where(
        (i) => i.category == category && !i.isExpansion && !i.isWishlist,
      )
      .length;

  List<CollectionItem> _pantheonItems() {
    if (!_pantheonConfigured) return const [];
    final games = _sharedItems()
        .where(
          (i) =>
              !i.isWishlist &&
              _activeCategories.contains(i.category) &&
              i.category != CollectionCategory.custom,
        )
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
    return picked.take(20).toList();
  }

  int get _visiblePantheonSlots {
    final filled = _pantheonIds.where((id) => id.isNotEmpty).length;
    if (filled < 10) return 10;
    if (filled >= 20) return 20;
    return filled + 1;
  }

  int get _ownedVisibleCount => hubOwnedItems(
        _sharedItems(),
        active: _activeCategories,
      ).length;

  List<PantheonCandidate> _pantheonCandidates() {
    return [
      for (final item in _sharedItems())
        if (_activeCategories.contains(item.category) &&
            item.category != CollectionCategory.custom)
          PantheonCandidate(
            id: item.id,
            title: item.title,
            bggId: item.metadata?['bgg_id']?.toString(),
            isExpansion: item.isExpansion,
            isWishlist: item.isWishlist,
            rating: item.rating ?? 0,
            plays: item.gamesPlayed ?? 0,
            bggRating: double.tryParse(
                  '${item.metadata?['bgg_avg_rating'] ?? ''}',
                ) ??
                0,
          ),
    ];
  }

  Future<void> _loadPantheon() async {
    final memory = PantheonMemory.instance.idsFor(widget.profileId);
    if (memory != null) {
      _pantheonIds = memory;
      _pantheonConfigured = memory.isNotEmpty;
      return;
    }
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
      if (unique.length == 20) break;
    }
    try {
      await ProfileService().savePantheonIds(unique);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pantheon_cap:${widget.profileId}', _pantheonCap);
    await prefs.setString('pantheon:${widget.profileId}', jsonEncode(unique));
    PantheonMemory.instance.publish(widget.profileId, unique);
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
      if (item.isWishlist ||
          item.isExpansion ||
          item.category == CollectionCategory.custom ||
          !_activeCategories.contains(item.category)) {
        continue;
      }
      final bgg = item.metadata?['bgg_id']?.toString().trim();
      final key = (bgg != null && bgg.isNotEmpty)
          ? 'bgg:$bgg'
          : 'title:${item.title.trim().toLowerCase()}';
      if (!seen.add(key)) continue;
      games.add(item);
    }
    games.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final picked = await showPantheonGamePicker(
      context,
      rank: index + 1,
      games: games,
    );
    if (picked == null) return;
    await _savePantheon(
      placeInPantheon(_pantheonIds, picked, targetIndex: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = ProfileAvatar.colorFromHex(widget.accentColor);

    return Scaffold(
      appBar: AppBar(
        title: widget.collectionView
            ? Text('Collection de ${widget.username}')
            : _mine
            ? const Text('Profil')
            : Row(
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
          if (!_mine)
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
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Accueil',
            onPressed: () => AppNavigation.openCollections(context),
          ),
        ],
      ),
      body: _loading &&
              _collectionItems.isEmpty &&
              _pantheonIds.isEmpty &&
              !(_mine && OwnProfilePanel.memory != null)
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _collectionItems.isEmpty && _pantheonIds.isEmpty
              ? Center(child: Text(_error!))
              : _buildProfile(),
    );
  }

  void _swapPantheon(int from, int to) {
    if (from == to || from < 0) return;
    final next = [..._pantheonIds];
    if (from >= next.length) return;
    if (to >= next.length) {
      next.add(next.removeAt(from));
    } else {
      final tmp = next[from];
      next[from] = next[to];
      next[to] = tmp;
    }
    _savePantheon(next);
  }

  void _openFriendCollection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendCollectionScreen(
          profileId: widget.profileId,
          username: widget.username,
          avatarUrl: widget.avatarUrl,
          accentColor: widget.accentColor,
          shareCollections: widget.shareCollections,
          collectionView: true,
        ),
      ),
    );
  }

  Widget _profileStats() {
    final owned = _ownedVisibleCount;
    final wishlist = _wishlistItems
        .where(
          (item) =>
              _activeCategories.contains(item.category) && !item.isExpansion,
        )
        .length;
    final plays = _sharedItems().fold<int>(
      0,
      (sum, item) => sum + (item.gamesPlayed ?? 0),
    );
    final tiles = [
      ('Objets possédés', '$owned', Icons.inventory_2_outlined),
      (
        'Collections actives',
        '${_activeCategories.length}',
        Icons.category_outlined,
      ),
      ('Wishlist', '$wishlist', Icons.favorite_border),
      ('Parties jouées', '$plays', Icons.sports_esports_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final children = [
          for (final (label, value, icon) in tiles)
            _statCard(label, value, icon),
        ];
        if (!wide) {
          return Wrap(spacing: 8, runSpacing: 8, children: children);
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 160,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _pantheonBlock() {
    if (!_mine && !_pantheonConfigured) return const SizedBox.shrink();
    return PantheonBento(
      ranked: _pantheonItems(),
      editable: _mine,
      slotCount: _visiblePantheonSlots,
      onOpenItem: (item) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ItemDetailScreen(item: item),
          ),
        );
      },
      onAutoFill: _mine && _pantheonIds.every((id) => id.isEmpty)
          ? () {
              _savePantheon(
                pickAutoPantheonIds(_pantheonCandidates(), limit: 10),
              );
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
      onReorder: _mine ? _swapPantheon : null,
    );
  }

  Widget _buildProfile() {
    if (!widget.collectionView) {
      final owned = _ownedVisibleCount;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_mine) const OwnProfilePanel(),
          if (_mine) ...[
            const SizedBox(height: 12),
            _profileStats(),
            const SizedBox(height: 16),
          ],
          _pantheonBlock(),
          if (!_mine) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _openFriendCollection,
              icon: const Text('📚'),
              label: Text('Voir sa collection ($owned objets)'),
            ),
          ],
        ],
      );
    }

    final overlapBanner = _overlapBanner();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
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
                    showCheckmark: false,
                    onSelected: (_) =>
                        setState(() => _scope = _ProfileScope.shared),
                  ),
                  ChoiceChip(
                    label: Text(
                      _mine
                          ? '📍 Actuellement chez toi'
                          : '📍 Actuellement chez ${widget.username}',
                    ),
                    selected: _scope == _ProfileScope.atHome,
                    showCheckmark: false,
                    onSelected: (_) =>
                        setState(() => _scope = _ProfileScope.atHome),
                  ),
                  ChoiceChip(
                    label: Text(
                      _mine
                          ? 'Ajoutés par toi'
                          : 'Ajoutés par ${widget.username}',
                    ),
                    selected: _scope == _ProfileScope.added,
                    showCheckmark: false,
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
                      showCheckmark: false,
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

class _ProfileSessionCache {
  final List<CollectionItem> collection;
  final List<CollectionItem> groups;
  final List<CollectionItem> wishlist;
  final bool? wishlistShared;
  final List<String> pantheonIds;
  final Set<CollectionCategory> active;

  const _ProfileSessionCache({
    required this.collection,
    required this.groups,
    required this.wishlist,
    required this.wishlistShared,
    required this.pantheonIds,
    required this.active,
  });

  static final Map<String, _ProfileSessionCache> _byId = {};

  static _ProfileSessionCache? of(String profileId) => _byId[profileId];

  static void save(
    String profileId, {
    required List<CollectionItem> collection,
    required List<CollectionItem> groups,
    required List<CollectionItem> wishlist,
    required bool? wishlistShared,
    required List<String> pantheonIds,
    required Set<CollectionCategory> active,
  }) {
    _byId[profileId] = _ProfileSessionCache(
      collection: List<CollectionItem>.from(collection),
      groups: List<CollectionItem>.from(groups),
      wishlist: List<CollectionItem>.from(wishlist),
      wishlistShared: wishlistShared,
      pantheonIds: List<String>.from(pantheonIds),
      active: Set<CollectionCategory>.from(active),
    );
  }
}
