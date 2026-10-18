import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../services/category_hub_preferences.dart';
import '../widgets/main_drawer.dart';
import '../models/user_collection_type.dart';
import '../models/user_profile.dart';
import '../utils/collection_grid_layout.dart';
import 'all_collection_screen.dart';
import 'books_collection_screen.dart';
import 'cards_collection_screen.dart';
import 'home_screen.dart';
import 'lego_collection_screen.dart';
import 'media_collection_screen.dart';
import 'movie_collection_screen.dart';
import 'stats_screen.dart';
import 'videogame_collection_screen.dart';
import 'tech_collection_screen.dart';
import 'watch_collection_screen.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import '../utils/category_hub_order.dart';
import '../utils/collection_item_scope.dart';
import '../models/collection_item.dart';
import '../utils/boardgame_expansions.dart';
import '../utils/hub_owned_count.dart';
import '../utils/hub_category_visibility.dart';
import '../utils/hub_greeting.dart';
import '../widgets/onboarding/onboarding_flow.dart';
import '../services/profile_cache_service.dart';
import '../widgets/notifications/notification_bell.dart';
import '../navigation/app_route_observer.dart';
import '../widgets/profile_avatar.dart';
import 'category_manage_screen.dart';
import 'wildlife/wildlife_collection_screen.dart';
import 'restaurant/restaurant_collection_screen.dart';

class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});

  @override
  State<CategorySelectionScreen> createState() =>
      _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen>
    with RouteAware {
  Map<CollectionCategory, int> _counts = {};
  Map<CollectionCategory, int> _groupCounts = {};
  Map<CollectionCategory, int> _wishlistCounts = {};
  Map<CollectionCategory, int> _duplicateCounts = {};
  int _boardgameExpansionCount = 0;
  bool _onboardingChecked = false;
  Map<String, int> _customCounts = {};
  bool _loadingCounts = true;
  List<HubTileEntry> _orderedTiles = [];
  @override
  void initState() {
    super.initState();
    ProfileCacheService.instance.addListener(_onProfileCacheChanged);
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
    ProfileCacheService.instance.removeListener(_onProfileCacheChanged);
    super.dispose();
  }

  @override
  void didPopNext() {
    _rollGreeting();
  }

  GrammarGender _grammar = GrammarGender.masculine;

  Future<void> _rollGreeting() async {
    if (!mounted) return;
    _grammar = await loadGrammarGender();
    if (!mounted) return;
    setState(() {
      _greeting = pickHubGreeting(
        username: _username,
        previous: _greeting?.name,
        grammar: _grammar,
      );
    });
  }

  void _onProfileCacheChanged() {
    if (mounted) setState(() {});
  }

  String get _username =>
      ProfileCacheService.instance.profile?.username ?? 'Aventurier';

  HubGreeting? _greeting;

  String get _greetingText {
    final g = _greeting;
    if (g == null || g.source == HubGreetingSource.pseudo) {
      return 'Salut $_username';
    }
    return g.text;
  }

  Color get _profileAccent {
    final hex = ProfileCacheService.instance.profile?.accentColor;
    return ProfileAvatar.colorFromHex(hex ?? profileAccentPresets.first);
  }

  Future<void> _load() async {
    setState(() => _loadingCounts = true);

    await CategoryHubPreferences.instance.load();
    final counts = emptyCategoryCounts();
    final groupCounts = emptyCategoryCounts();
    final wishCounts = emptyCategoryCounts();
    final customCounts = <String, int>{};
    final duplicateCounts = <CollectionCategory, int>{};
    var boardgameExpansionCount = 0;
    var orderedTiles = <HubTileEntry>[];
    String? loadError;

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      const hubSelect =
          'id, title, quantity, category, subcategory, is_wishlist, is_sold, '
          'is_expansion, parent_game_id, added_by, metadata';
      final rows = await CollectionItemScope.ownedByUser(
        Supabase.instance.client
            .from('collection_items')
            .select(hubSelect),
        userId: userId,
      );

      final boardgameRows = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      final ownedMaps = <Map<String, dynamic>>[];

      void collectOwned(Map<String, dynamic> map) {
        final id = map['id']?.toString() ?? '';
        if (id.isNotEmpty && !seenIds.add(id)) return;
        if (_hubRowFlag(map, 'is_wishlist') || _hubRowFlag(map, 'is_sold')) {
          return;
        }
        ownedMaps.add(map);
        if (CollectionCategory.fromDbValue(map['category'] as String) ==
            CollectionCategory.boardgame) {
          boardgameRows.add(map);
        }
      }

      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        if (_hubRowFlag(map, 'is_wishlist') && !_hubRowIsExpansion(map)) {
          final cat = CollectionCategory.fromDbValue(map['category'] as String);
          if (cat != CollectionCategory.custom) {
            wishCounts[cat] = (wishCounts[cat] ?? 0) + 1;
          }
        }
        collectOwned(map);
      }

      boardgameExpansionCount = countUniqueOwnedExpansions(boardgameRows);

      try {
        final groupIds = await CollectionItemScope.myGroupIds(userId);
        if (groupIds.isNotEmpty) {
          final gRows = await Supabase.instance.client
              .from('collection_items')
              .select(hubSelect)
              .inFilter('group_id', groupIds);
          for (final row in gRows as List) {
            collectOwned(Map<String, dynamic>.from(row as Map));
          }
          boardgameExpansionCount = countUniqueOwnedExpansions(boardgameRows);
        }
      } catch (_) {
        // group_members RLS : compteurs perso OK, groupes ignorés
      }

      final visible = visibleOwnedLikeGrid([
        for (final map in ownedMaps) CollectionItem.fromJson(map),
      ]);
      final byCategory = <CollectionCategory, List<CollectionItem>>{};
      for (final item in visible) {
        if (item.category == CollectionCategory.custom) {
          final sub = item.subcategory;
          if (sub != null) customCounts[sub] = (customCounts[sub] ?? 0) + 1;
          continue;
        }
        counts[item.category] = (counts[item.category] ?? 0) + 1;
        byCategory.putIfAbsent(item.category, () => []).add(item);
      }
      for (final entry in byCategory.entries) {
        final n = countDuplicateGames(entry.value);
        if (n > 0) duplicateCounts[entry.key] = n;
      }

      orderedTiles = await loadVisibleHubTiles();
    } catch (e) {
      loadError = e.toString();
    }

    if (mounted) {
      _grammar = await loadGrammarGender();
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _groupCounts = groupCounts;
        _wishlistCounts = wishCounts;
        _duplicateCounts = duplicateCounts;
        _boardgameExpansionCount = boardgameExpansionCount;
        _customCounts = customCounts;
        _orderedTiles = orderedTiles;
        _greeting ??= pickHubGreeting(
          username: _username,
          grammar: _grammar,
        );
        _loadingCounts = false;
      });
      _maybeShowOnboarding(
        counts,
        groupCounts,
        customCounts,
        failed: loadError != null,
      );
      if (loadError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              loadError.contains('infinite recursion')
                  ? 'Erreur base de données (groupes). '
                      'Exécute supabase/schema_rls_group_members_fix.sql '
                      'dans Supabase.'
                  : 'Chargement partiel : $loadError',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  void _maybeShowOnboarding(
    Map<CollectionCategory, int> counts,
    Map<CollectionCategory, int> groupCounts,
    Map<String, int> customCounts, {
    required bool failed,
  }) {
    if (_onboardingChecked || !mounted || failed) return;
    _onboardingChecked = true;
    final total = counts.values.fold<int>(0, (a, b) => a + b) +
        groupCounts.values.fold<int>(0, (a, b) => a + b) +
        customCounts.values.fold<int>(0, (a, b) => a + b);
    if (total != 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showOnboardingIfNeeded(context);
    });
  }

  void _openCategory(CollectionCategory category) {
    AppHaptics.selection();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => switch (category) {
          CollectionCategory.boardgame => const HomeScreen(
              category: CollectionCategory.boardgame,
              screenTitle: 'Mes jeux de société',
              accentOverride: Colors.orange,
            ),
          CollectionCategory.book => const BooksCollectionScreen(),
          CollectionCategory.card => const CardsCollectionScreen(),
          CollectionCategory.media => const MediaCollectionScreen(),
          CollectionCategory.lego => const LegoCollectionScreen(),
          CollectionCategory.watch => const WatchCollectionScreen(),
          CollectionCategory.videogame => const VideogameCollectionScreen(),
          CollectionCategory.movie => const MovieCollectionScreen(),
          CollectionCategory.wildlife => const WildlifeCollectionScreen(),
          CollectionCategory.restaurant => const RestaurantCollectionScreen(),
          CollectionCategory.tech => const TechCollectionScreen(),
          _ => HomeScreen(category: category),
        },
      ),
    ).then((_) => _load());
  }

  void _openCustomType(UserCollectionType type) {
    AppHaptics.selection();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(
          category: CollectionCategory.custom,
          screenTitle: type.name,
          customTypeId: type.id,
          customTypeName: type.name,
          accentOverride: type.color,
        ),
      ),
    ).then((_) => _load());
  }

  Future<void> _openManageCollections() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoryManageScreen()),
    );
    if (mounted) _load();
  }

  int get _gridItemCount => _orderedTiles.length + 1;

  void _onReorderTiles(int from, int to) {
    if (from == to || from < 0 || to < 0) return;
    if (from >= _orderedTiles.length || to >= _orderedTiles.length) return;
    setState(() {
      final next = List<HubTileEntry>.from(_orderedTiles);
      final item = next.removeAt(from);
      next.insert(to, item);
      _orderedTiles = next;
    });
    CategoryHubOrder.saveTileOrder(_orderedTiles);
    AppHaptics.selection();
  }

  Widget _wrapDraggableTile(int index, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return LongPressDraggable<int>(
      data: index,
      delay: const Duration(milliseconds: 220),
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        color: scheme.surface,
        child: SizedBox(width: 148, height: 172, child: child),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != index,
        onAcceptWithDetails: (d) => _onReorderTiles(d.data, index),
        builder: (context, candidate, rejected) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: candidate.isNotEmpty
                ? BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(20),
                  )
                : null,
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildGridItem(int index) {
    if (index < _orderedTiles.length) {
      final entry = _orderedTiles[index];
      final child = entry.category != null
          ? _buildCategoryCard(entry.category!)
          : _buildCustomTypeCard(entry.customType!);
      return _AnimatedCategoryCard(
        index: index,
        child: _wrapDraggableTile(index, child),
      );
    }
    return _AnimatedCategoryCard(
      index: index,
      child: _buildManageCollectionsCard(),
    );
  }

  void _openStats() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => const StatsScreen()),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = scheme.onSurfaceVariant;
    final accent = _profileAccent;
    final greetingStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
        actions: [
          const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Statistiques — tableau de bord de ta collection',
            onPressed: _openStats,
          ),
        ],
      ),
      drawer: const MainDrawer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            decoration: AppTheme.heroGradient(
              accent,
              brightness: Theme.of(context).brightness,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDark)
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        accent,
                        Colors.white.withValues(alpha: 0.88),
                      ],
                    ).createShader(bounds),
                    child: Text(
                      _greetingText,
                      style: greetingStyle?.copyWith(color: Colors.white),
                    ),
                  )
                else
                  Text(
                    _greetingText,
                    style: greetingStyle?.copyWith(
                      color: Color.lerp(accent, const Color(0xFF1A1033), 0.72),
                    ),
                  ),
                Text(
                  'Quelle collection ouvrir ?',
                  style: TextStyle(
                    fontSize: 13,
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
          ),
          _buildAllCollectionBanner(accent),
          Expanded(
            child: _loadingCounts
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: CollectionGridLayout.gridDelegate(
                      context,
                      mobileColumns: 2,
                      childAspectRatio: 0.88,
                      spacing: 14,
                    ),
                    itemCount: _gridItemCount,
                    itemBuilder: (context, index) => _buildGridItem(index),
                  ),
          ),
        ],
      ),
    );
  }

  int get _totalOwned {
    var n = 0;
    for (final entry in _orderedTiles) {
      if (entry.category != null) {
        n += _counts[entry.category] ?? 0;
        n += _groupCounts[entry.category] ?? 0;
      } else if (entry.customType != null) {
        n += _customCounts[entry.customType!.id] ?? 0;
      }
    }
    return n;
  }

  Widget _buildAllCollectionBanner(Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final total = _totalOwned;
    final icons = [
      for (final e in _orderedTiles.take(5))
        if (e.category != null) (e.category!.icon, e.category!.color),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            AppHaptics.selection();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AllCollectionScreen()),
            ).then((_) => _load());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.all_inbox_rounded, color: accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Toute ma collection',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _loadingCounts
                            ? 'Toutes catégories confondues'
                            : '$total objet${total > 1 ? 's' : ''} · toutes catégories',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final (icon, color) in icons)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: color.withValues(alpha: 0.18),
                      child: Icon(icon, size: 14, color: color),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(CollectionCategory category) {
    final count = _counts[category] ?? 0;
    final groupCount = _groupCounts[category] ?? 0;
    final wishCount = _wishlistCounts[category] ?? 0;
    final total = count + groupCount;
    final countLabel = category.countSummary(total);
    final wishLabel = wishCount > 0 ? '♥ $wishCount en wishlist' : null;
    final dup = _duplicateCounts[category] ?? 0;
    final expansionCount = category == CollectionCategory.boardgame
        ? _boardgameExpansionCount
        : 0;
    final expansionLabel = expansionCount > 0
        ? expansionCount == 1
            ? '1 extension'
            : '$expansionCount extensions'
        : null;

    return InkWell(
      onTap: () => _openCategory(category),
      borderRadius: BorderRadius.circular(20),
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    category.color.withValues(alpha: 0.2),
                    category.color.withValues(alpha: 0.06),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(category.icon, size: 36, color: category.color),
            ),
            const SizedBox(height: 12),
            Text(
              category.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                category.description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                dup > 0 ? '$countLabel · Double(s) : $dup' : countLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: category.color),
              ),
            ),
            if (wishLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                wishLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.amber.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (expansionLabel != null) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.extension_outlined,
                    size: 12,
                    color: Colors.green.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    expansionLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCustomTypeCard(UserCollectionType type) {
    final count = _customCounts[type.id] ?? 0;
    final countLabel =
        count == 0 ? 'Vide' : (count == 1 ? '1 objet' : '$count objets');

    return InkWell(
      onTap: () => _openCustomType(type),
      borderRadius: BorderRadius.circular(20),
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    type.color.withValues(alpha: 0.2),
                    type.color.withValues(alpha: 0.06),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(type.icon, size: 36, color: type.color),
            ),
            const SizedBox(height: 12),
            Text(
              type.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              countLabel,
              style: TextStyle(fontSize: 12, color: type.color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageCollectionsCard() {
    return InkWell(
      onTap: _openManageCollections,
      borderRadius: BorderRadius.circular(20),
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tune, size: 40, color: Colors.grey.shade700),
            const SizedBox(height: 12),
            Text(
              'Gestion des collections',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Masquer, ajouter ou supprimer',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedCategoryCard extends StatelessWidget {
  final int index;
  final Widget child;

  const _AnimatedCategoryCard({
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final delay = Duration(milliseconds: 35 * index.clamp(0, 12));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }
}

bool _hubRowFlag(Map<String, dynamic> map, String key) {
  final v = map[key];
  return v == true || v == 'true' || v == 1;
}

bool _hubRowIsExpansion(Map<String, dynamic> map) {
  if (_hubRowFlag(map, 'is_expansion')) return true;
  final parent = map['parent_game_id']?.toString();
  if (parent != null && parent.isNotEmpty) return true;
  final meta = map['metadata'];
  return meta is Map && meta['bgg_is_expansion'] == true;
}
