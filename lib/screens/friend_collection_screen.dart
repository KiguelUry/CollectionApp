import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/friend_service.dart';
import '../services/player_alias_service.dart';
import '../services/profile_cache_service.dart';
import '../services/profile_service.dart';
import 'global_play_history_screen.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_grid_layout.dart';
import '../navigation/app_navigation.dart';
import '../navigation/app_route_observer.dart';
import '../services/pantheon_memory.dart';
import '../utils/copy_friend_item.dart';
import '../utils/friend_item_overlap.dart';
import '../utils/active_categories.dart';
import '../utils/hub_owned_count.dart';
import '../utils/item_search.dart';
import '../utils/pantheon_ranking.dart';
import '../widgets/collection_cover_image.dart';
import '../widgets/collection_item_tile.dart';
import '../widgets/profile/own_profile_panel.dart';
import '../widgets/profile/pantheon_bento.dart';
import '../widgets/profile_avatar.dart';
import 'item_detail_screen.dart';

/// Filtre rapide de la collection d'un ami.
enum FriendQuickFilter { all, common, discover, groups }

/// Profil et collection d'un ami (lecture seule), ou mon propre profil.
class FriendCollectionScreen extends StatefulWidget {
  final String profileId;
  final String username;
  final String? avatarUrl;
  final String? accentColor;
  final bool shareCollections;
  final bool collectionView;
  /// Ouvre directement l'onglet Wishlist (vue collection).
  final bool initialWishlist;

  const FriendCollectionScreen({
    super.key,
    required this.profileId,
    required this.username,
    this.avatarUrl,
    this.accentColor,
    this.collectionView = false,
    this.initialWishlist = false,
    required this.shareCollections,
  });

  @override
  State<FriendCollectionScreen> createState() => _FriendCollectionScreenState();
}

class _FriendCollectionScreenState extends State<FriendCollectionScreen>
    with RouteAware {
  static const _darkBg = Color(0xFF14161B);

  final _friendService = FriendService();
  final _search = TextEditingController();
  List<CollectionItem> _collectionItems = [];
  List<CollectionItem> _groupItems = [];
  List<CollectionItem> _wishlistItems = [];
  Set<String> _commonGroupIds = {};
  bool? _wishlistShared;
  bool _loading = true;
  String? _error;
  CollectionCategory _selectedCategory = CollectionCategory.boardgame;
  FriendOverlapIndex _overlap = FriendOverlapIndex.empty;
  bool _categorySynced = false;
  FriendQuickFilter _quick = FriendQuickFilter.all;
  late bool _showWishlist = widget.initialWishlist;
  List<String> _pantheonIds = [];
  int _pantheonCap = 10;
  bool _pantheonConfigured = false;
  bool _mine = false;
  String? _bio;
  int? _playsTogether;
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
      _commonGroupIds = cached.commonGroupIds;
      _pantheonIds = List<String>.from(cached.pantheonIds);
      _pantheonConfigured = cached.pantheonIds.isNotEmpty;
      _activeCategories = cached.active;
      _bio = cached.bio;
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
    _search.addListener(() => setState(() {}));
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
    _search.dispose();
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
    final keepShown =
        silent || _collectionItems.isNotEmpty || _pantheonIds.isNotEmpty;
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
      final results = await Future.wait([
        _friendService.fetchFriendCollectionItems(widget.profileId),
        _friendService.fetchItemsInCommonGroups(widget.profileId),
        _friendService.commonGroupIds(widget.profileId),
        _friendService.canViewFriendWishlist(widget.profileId),
      ]);
      // Filet de sécurité : jamais mes objets dans la vue d'un autre profil.
      final friendId = widget.profileId;
      _collectionItems = (results[0] as List<CollectionItem>)
          .where((i) => _mine || i.addedBy == friendId)
          .toList();
      _groupItems = results[1] as List<CollectionItem>;
      _commonGroupIds = results[2] as Set<String>;
      _wishlistShared = results[3] as bool;
      _wishlistItems = _wishlistShared == true
          ? (await _friendService.fetchFriendWishlistItems(friendId))
              .where((i) => _mine || i.addedBy == friendId)
              .toList()
          : [];
      _overlap = _mine
          ? FriendOverlapIndex.empty
          : await buildFriendOverlapIndex([
              ..._collectionItems,
              ..._groupItems,
              ..._wishlistItems,
            ]);
      _activeCategories = await ActiveCategories.load();
      await _loadPantheon();
      if (!_mine) {
        try {
          _bio = (await ProfileService().fetchProfile(widget.profileId)).bio;
        } catch (_) {}
        _playsTogether = await _countPlaysTogether();
      }
      _categorySynced = false;
      _error = null;
    } catch (e) {
      if (!keepShown) {
        _collectionItems = [];
        _wishlistItems = [];
        _overlap = FriendOverlapIndex.empty;
        _error = e.toString();
      }
    }

    if (mounted) {
      if (_error == null) {
        _ProfileSessionCache.save(
          widget.profileId,
          _ProfileSessionCache(
            collection: List.of(_collectionItems),
            groups: List.of(_groupItems),
            wishlist: List.of(_wishlistItems),
            wishlistShared: _wishlistShared,
            commonGroupIds: Set.of(_commonGroupIds),
            pantheonIds: List.of(_pantheonIds),
            active: Set.of(_activeCategories),
            bio: _bio,
          ),
        );
      }
      setState(() => _loading = false);
      _pickInitialCategory([..._collectionItems, ..._wishlistItems]);
    }
  }

  /// Pseudos « moi » (identité isMe + username) — jamais confondus avec un ami.
  Future<Set<String>> _myPlayNames() async {
    await PlayerAliasService.instance.ensureLoaded();
    final names = <String>{};
    final me = PlayerAliasService.instance.meIdentity;
    if (me != null) {
      for (final n in me.names) {
        final t = n.trim().toLowerCase();
        if (t.isNotEmpty) names.add(t);
      }
      final d = me.displayName.trim().toLowerCase();
      if (d.isNotEmpty) names.add(d);
    }
    final user =
        ProfileCacheService.instance.profile?.username.trim().toLowerCase();
    if (user != null && user.isNotEmpty) names.add(user);
    return names;
  }

  /// Pseudos de cet ami : lien identité → profileId, sinon username
  /// (sauf si ce username est déjà « moi » — cas Kiki).
  Future<Set<String>> _friendPlayNames(Set<String> meNames) async {
    await PlayerAliasService.instance.ensureLoaded();
    final names = <String>{};
    for (final id in PlayerAliasService.instance.identities) {
      if (id.isMe) continue;
      if (id.friendProfileId != widget.profileId) continue;
      for (final n in id.names) {
        final t = n.trim().toLowerCase();
        if (t.isNotEmpty) names.add(t);
      }
      final d = id.displayName.trim().toLowerCase();
      if (d.isNotEmpty) names.add(d);
      final fu = id.friendUsername?.trim().toLowerCase();
      if (fu != null && fu.isNotEmpty) names.add(fu);
    }
    final friendUser = widget.username.trim().toLowerCase();
    if (friendUser.isNotEmpty && !meNames.contains(friendUser)) {
      names.add(friendUser);
    }
    names.removeAll(meNames);
    return names;
  }

  /// Parties où vous apparaissez tous les deux (mon historique + le sien).
  Future<int> _countPlaysTogether() async {
    final meNames = await _myPlayNames();
    final friendNames = await _friendPlayNames(meNames);
    if (friendNames.isEmpty && meNames.isEmpty) return 0;
    final keys = <String>{};
    void scan(Iterable<CollectionItem> items, Set<String> lookingFor) {
      if (lookingFor.isEmpty) return;
      for (final item in items) {
        final plays = item.metadata?['boardgame_plays'];
        if (plays is! List) continue;
        for (final p in plays) {
          if (p is! Map) continue;
          final players = {
            for (final n in (p['players'] as List? ?? const []))
              n.toString().trim().toLowerCase(),
          }..removeWhere((e) => e.isEmpty);
          if (!players.any(lookingFor.contains)) continue;
          final game = item.metadata?['bgg_id']?.toString() ??
              item.title.trim().toLowerCase();
          final date = p['date']?.toString() ?? '';
          final day = date.length >= 10 ? date.substring(0, 10) : date;
          keys.add(p['share_id']?.toString() ?? '$game|$day');
        }
      }
    }

    // Mes parties où l'ami apparaît (via identité liée, pas mon pseudo).
    scan(await myOverlapItems(), friendNames);
    // Parties de l'ami où j'apparais.
    scan([..._collectionItems, ..._groupItems], meNames);
    return keys.length;
  }

  Future<void> _openPlaysTogether() async {
    final meNames = await _myPlayNames();
    final friendNames = await _friendPlayNames(meNames);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GlobalPlayHistoryScreen(
          playerNameFilter: friendNames.toList(),
          filterTitle: 'Avec ${widget.username}',
        ),
      ),
    );
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

  /// Collection de l'ami + groupes communs (dédoublonnés par id).
  /// Réservé à la vue "moi" / filtre Groupes — jamais pour stats/Panthéon ami.
  List<CollectionItem> _sharedItems() {
    final byId = <String, CollectionItem>{};
    for (final item in [..._collectionItems, ..._groupItems]) {
      byId[item.id] = item;
    }
    return byId.values.toList();
  }

  /// Objets qui représentent l'identité collection du profil affiché.
  /// Chez un ami : uniquement ses `added_by` (pas les copies du foyer).
  List<CollectionItem> _identityItems() =>
      _mine ? _sharedItems() : _collectionItems;

  List<CollectionItem> _baseItems() {
    if (_showWishlist) return _wishlistItems;
    if (_quick == FriendQuickFilter.groups) return _groupItems;
    return _collectionItems;
  }

  bool _passesQuick(CollectionItem item, FriendQuickFilter f) {
    switch (f) {
      case FriendQuickFilter.all:
      case FriendQuickFilter.groups:
        return true;
      case FriendQuickFilter.common:
        return _overlap.kindFor(item) != FriendOverlapKind.none;
      case FriendQuickFilter.discover:
        return _overlap.kindFor(item) == FriendOverlapKind.none;
    }
  }

  List<CollectionItem> _visibleFor(
    CollectionCategory category, {
    FriendQuickFilter? quick,
  }) {
    final f = quick ?? _quick;
    final base = (!_showWishlist && f == FriendQuickFilter.groups)
        ? _groupItems
        : _baseItems();
    final q = _search.text;
    return base
        .where(
          (i) =>
              i.category == category &&
              _passesQuick(i, f) &&
              itemMatchesSearch(i, q),
        )
        .toList();
  }

  int _countFor(CollectionCategory category) => _visibleFor(category)
      .where((i) => !i.isExpansion)
      .length;

  int _quickCount(FriendQuickFilter f) => _visibleFor(
        _selectedCategory,
        quick: f,
      ).where((i) => !i.isExpansion).length;

  List<CollectionItem> _pantheonItems() {
    if (!_pantheonConfigured) return const [];
    final games = _identityItems()
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
        _identityItems(),
        active: _activeCategories,
      ).length;

  int get _wishlistVisibleCount => _wishlistItems
      .where(
        (item) => _activeCategories.contains(item.category) && !item.isExpansion,
      )
      .length;

  int get _commonCount => _overlap.countIn(
        hubOwnedItems(_collectionItems, active: _activeCategories),
        FriendOverlapKind.inCollection,
      );

  List<PantheonCandidate> _pantheonCandidates() {
    return [
      for (final item in _identityItems())
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
      _pantheonIds = decoded
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toList();
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
    for (final item in _identityItems()) {
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
    games.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
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
    final friendProfile = !_mine && !widget.collectionView;
    return Scaffold(
      backgroundColor: friendProfile ? _darkBg : null,
      appBar: AppBar(
        backgroundColor: _darkBg,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: widget.collectionView && !_mine
            ? Row(
                children: [
                  ProfileAvatar(
                    avatarUrl: widget.avatarUrl,
                    accentColorHex: widget.accentColor,
                    fallbackInitial: widget.username,
                    radius: 14,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Chez ${widget.username}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(
                widget.collectionView
                    ? (_mine ? 'Ma collection' : 'Chez ${widget.username}')
                    : (_mine ? 'Profil' : widget.username),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Accueil',
            onPressed: () => AppNavigation.openCollections(context),
          ),
        ],
      ),
      body: ColoredBox(
        color: (friendProfile || (!_mine && widget.collectionView))
            ? _darkBg
            : Colors.transparent,
        child: _loading &&
                _collectionItems.isEmpty &&
                _pantheonIds.isEmpty &&
                !(_mine && OwnProfilePanel.memory != null)
            ? const Center(child: CircularProgressIndicator())
            : _error != null &&
                    _collectionItems.isEmpty &&
                    _pantheonIds.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: friendProfile || !_mine
                              ? Colors.white70
                              : null,
                        ),
                      ),
                    ),
                  )
                : widget.collectionView
                    ? _buildCollection()
                    : _buildProfile(),
      ),
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

  void _openFriendCollection({bool wishlist = false}) {
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
          initialWishlist: wishlist,
        ),
      ),
    );
  }

  void _openItem(CollectionItem item, {int? quantity}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(
          item: quantity == null ? item : item.copyWith(quantity: quantity),
          readOnly: !_mine,
          friendUsername: _mine ? null : widget.username,
          friendOverlap: _mine ? null : _overlap.kindFor(item),
        ),
      ),
    );
  }

  Widget _profileStats() {
    final owned = _ownedVisibleCount;
    final plays = _identityItems().fold<int>(
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
      ('Wishlist', '$_wishlistVisibleCount', Icons.favorite_border),
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
    // Toujours afficher le bloc chez un ami (même vide) — sinon profil « triste ».
    if (!_mine && !_pantheonConfigured) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined,
                color: Colors.amber.shade300, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Panthéon de ${widget.username} pas encore configuré',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return PantheonBento(
      ranked: _pantheonItems(),
      editable: _mine,
      slotCount: _visiblePantheonSlots,
      onOpenItem: _openItem,
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
    if (_mine) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const OwnProfilePanel(),
          const SizedBox(height: 12),
          _profileStats(),
          const SizedBox(height: 16),
          _pantheonBlock(),
        ],
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            _FriendHeader(
              username: widget.username,
              avatarUrl: widget.avatarUrl,
              accentColor: widget.accentColor,
              bio: _bio,
              owned: _ownedVisibleCount,
              common: _commonCount,
              playsTogether: _playsTogether,
              onPlaysTogetherTap: (_playsTogether ?? 0) > 0
                  ? _openPlaysTogether
                  : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _DarkActionButton(
                    icon: Icons.grid_view_rounded,
                    label: 'Collection',
                    count: _ownedVisibleCount,
                    onTap: () => _openFriendCollection(),
                  ),
                ),
                if (_wishlistShared == true) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DarkActionButton(
                      icon: Icons.favorite_border_rounded,
                      label: 'Wishlist',
                      count: _wishlistVisibleCount,
                      onTap: () => _openFriendCollection(wishlist: true),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Theme(
              data: ThemeData.dark(useMaterial3: true),
              child: _pantheonBlock(),
            ),
            const SizedBox(height: 16),
            _recentAddsRibbon(),
            const SizedBox(height: 18),
            if ((_playsTogether ?? 0) > 0)
              _playsTogetherBlock()
            else
              _playsTogetherHint(),
          ],
        ),
      ),
    );
  }

  Widget _playsTogetherHint() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_outlined, color: Colors.white38, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aucune partie ensemble pour l’instant. '
              'Lie « ${widget.username} » dans Identités joueurs '
              '(Parties → Identités) pour compter les parties.',
              style: const TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playsTogetherBlock() {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openPlaysTogether,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(Icons.sports_esports_rounded,
                  color: Colors.orangeAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_playsTogether ?? 0} partie${(_playsTogether ?? 0) > 1 ? 's' : ''} ensemble',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Text(
                'avec ${widget.username}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentAddsRibbon() {
    final recent = [..._collectionItems]
      ..sort((a, b) {
        final ac = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bc = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bc.compareTo(ac);
      });
    final top = recent.where((i) => !i.isExpansion).take(5).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ajouts récents',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: top.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final item = top[i];
              return InkWell(
                onTap: () => _openItem(item),
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 84,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: item.imageUrl != null &&
                                  item.imageUrl!.isNotEmpty
                              ? CollectionCoverImage(
                                  url: item.imageUrl!,
                                  fit: BoxFit.cover,
                                  bookCover:
                                      item.category == CollectionCategory.book,
                                )
                              : ColoredBox(
                                  color: Colors.white12,
                                  child: Icon(
                                    item.category.icon,
                                    color: Colors.white54,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCollection() {
    final scheme = Theme.of(context).colorScheme;
    final hasGroups = _commonGroupIds.isNotEmpty && _groupItems.isNotEmpty;
    if (!hasGroups && _quick == FriendQuickFilter.groups) {
      _quick = FriendQuickFilter.all;
    }
    final quickFilters = <(FriendQuickFilter, String)>[
      (FriendQuickFilter.all, 'Tous'),
      if (!_mine) (FriendQuickFilter.common, 'En commun'),
      if (!_mine) (FriendQuickFilter.discover, 'À découvrir'),
      if (hasGroups && !_showWishlist)
        (FriendQuickFilter.groups, 'Groupes communs'),
    ];
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (_wishlistShared == true)
                Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: IntrinsicWidth(
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.white.withValues(alpha: 0.14);
                              }
                              return Colors.transparent;
                            }),
                            foregroundColor: WidgetStateProperty.all(
                              Colors.white,
                            ),
                            side: WidgetStateProperty.all(BorderSide.none),
                          ),
                          segments: [
                            ButtonSegment(
                              value: false,
                              icon: const Icon(
                                Icons.grid_view_rounded,
                                size: 16,
                              ),
                              label: Text('Collection · $_ownedVisibleCount'),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: const Icon(
                                Icons.favorite_border_rounded,
                                size: 16,
                              ),
                              label: Text('Wishlist · $_wishlistVisibleCount'),
                            ),
                          ],
                          selected: {_showWishlist},
                          onSelectionChanged: (s) => setState(() {
                            _showWishlist = s.first;
                            if (_showWishlist &&
                                _quick == FriendQuickFilter.groups) {
                              _quick = FriendQuickFilter.all;
                            }
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Rechercher chez ${widget.username}…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: _search.clear,
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final (f, label) in quickFilters) ...[
                      _QuickPill(
                        label: label,
                        count: _quickCount(f),
                        selected: _quick == f,
                        onTap: () => setState(() => _quick = f),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: PopupMenuButton<CollectionCategory>(
                  tooltip: 'Changer de collection',
                  onSelected: (c) => setState(() => _selectedCategory = c),
                  itemBuilder: (_) => [
                    for (final cat in _visibleCategories)
                      PopupMenuItem(
                        value: cat,
                        child: Row(
                          children: [
                            Icon(cat.icon, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(cat.label)),
                            Text(
                              '${_countFor(cat)}',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_selectedCategory.icon, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedCategory.label} (${_countFor(_selectedCategory)})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
        _buildCategoryGridSliver(_selectedCategory),
      ],
    );
  }

  List<CollectionCategory> get _visibleCategories {
    final cats = CollectionCategory.values
        .where((c) => _activeCategories.contains(c))
        .where((c) => _countFor(c) > 0 || c == _selectedCategory)
        .toList();
    if (cats.isEmpty) {
      return CollectionCategory.values
          .where((c) => _activeCategories.contains(c))
          .toList();
    }
    return cats;
  }

  Widget _buildCategoryGridSliver(CollectionCategory category) {
    final items = _visibleFor(category)
      ..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    if (items.isEmpty) {
      final msg = switch (_quick) {
        _ when _search.text.trim().isNotEmpty => 'Aucun résultat.',
        FriendQuickFilter.common => 'Aucun objet en commun ici.',
        FriendQuickFilter.discover => 'Tu as déjà tout ce qu\'il a ici !',
        _ => 'Rien dans cette catégorie.',
      };
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Text(msg, textAlign: TextAlign.center),
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
            final overlap = _mine ? null : _overlap.kindFor(item);

            return CollectionItemTile(
              item: item,
              category: category,
              totalQuantity: entry.totalQuantity,
              showDuplicateBadge: entry.hasDuplicates,
              overlapKind: overlap == FriendOverlapKind.none ? null : overlap,
              onTap: () => _openItem(item, quantity: entry.totalQuantity),
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

/// En-tête sombre : avatar, pseudo, bio et 3 mini-stats sur une ligne.
class _FriendHeader extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final String? accentColor;
  final String? bio;
  final int owned;
  final int common;
  final int? playsTogether;
  final VoidCallback? onPlaysTogetherTap;

  const _FriendHeader({
    required this.username,
    required this.avatarUrl,
    required this.accentColor,
    required this.bio,
    required this.owned,
    required this.common,
    required this.playsTogether,
    this.onPlaysTogetherTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ProfileAvatar.colorFromHex(accentColor);
    final bioText = bio?.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(const Color(0xFF1E2128), accent, 0.28)!,
            const Color(0xFF1A1C22),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 2),
                ),
                child: ProfileAvatar(
                  avatarUrl: avatarUrl,
                  accentColorHex: accentColor,
                  fallbackInitial: username,
                  radius: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (bioText != null && bioText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bioText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(value: '$owned', label: 'objets'),
              _statDivider(),
              _MiniStat(value: '$common', label: 'en commun'),
              _statDivider(),
              _MiniStat(
                value: playsTogether == null ? '–' : '$playsTogether',
                label: 'parties ensemble',
                onTap: onPlaysTogetherTap,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 26,
        color: Colors.white.withValues(alpha: 0.12),
      );
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _MiniStat({
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            decoration: onTap != null ? TextDecoration.underline : null,
            decorationColor: Colors.white38,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11.5,
          ),
        ),
      ],
    );
    return Expanded(
      child: onTap == null
          ? col
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: col,
              ),
            ),
    );
  }
}

class _DarkActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _DarkActionButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pilule de filtre rapide (sans coche, contraste neutre).
class _QuickPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _QuickPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.surface : scheme.onSurface;
    return Material(
      color: selected ? scheme.onSurface : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Text(
              '$label · $count',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
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
  final Set<String> commonGroupIds;
  final List<String> pantheonIds;
  final Set<CollectionCategory> active;
  final String? bio;

  const _ProfileSessionCache({
    required this.collection,
    required this.groups,
    required this.wishlist,
    required this.wishlistShared,
    required this.commonGroupIds,
    required this.pantheonIds,
    required this.active,
    required this.bio,
  });

  static final Map<String, _ProfileSessionCache> _byId = {};

  static _ProfileSessionCache? of(String profileId) => _byId[profileId];

  static void save(String profileId, _ProfileSessionCache entry) {
    _byId[profileId] = entry;
  }
}
