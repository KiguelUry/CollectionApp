import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../services/category_hub_preferences.dart';
import '../services/recommendation_service.dart';
import '../widgets/recommendations_banner.dart';
import '../widgets/main_drawer.dart';
import '../models/user_collection_type.dart';
import '../models/user_profile.dart';
import '../utils/collection_grid_layout.dart';
import 'books_collection_screen.dart';
import 'boardgame/boardgames_collection_screen.dart';
import 'cards_collection_screen.dart';
import 'home_screen.dart';
import 'lego_collection_screen.dart';
import 'media_collection_screen.dart';
import 'movie_collection_screen.dart';
import 'stats_screen.dart';
import 'videogame_collection_screen.dart';
import 'watch_collection_screen.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import '../utils/category_hub_order.dart';
import '../utils/collection_item_scope.dart';
import '../utils/hub_category_visibility.dart';
import '../services/profile_cache_service.dart';
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

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  final _recommendations = RecommendationService();
  Map<CollectionCategory, int> _counts = {};
  Map<CollectionCategory, int> _groupCounts = {};
  Map<CollectionCategory, int> _wishlistCounts = {};
  Map<String, int> _customCounts = {};
  bool _loadingCounts = true;
  List<HubTileEntry> _orderedTiles = [];
  List<Recommendation> _recommendationsList = [];

  @override
  void initState() {
    super.initState();
    ProfileCacheService.instance.addListener(_onProfileCacheChanged);
    _load();
  }

  @override
  void dispose() {
    ProfileCacheService.instance.removeListener(_onProfileCacheChanged);
    super.dispose();
  }

  void _onProfileCacheChanged() {
    if (mounted) setState(() {});
  }

  String get _username =>
      ProfileCacheService.instance.profile?.username ?? 'Aventurier';

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
    var orderedTiles = <HubTileEntry>[];
    var recommendationsList = <Recommendation>[];
    String? loadError;

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final rows = await CollectionItemScope.personal(
        Supabase.instance.client
            .from('collection_items')
            .select('category, subcategory, is_wishlist'),
        userId: userId,
      );

      for (final row in rows as List) {
        final cat = CollectionCategory.fromDbValue(row['category'] as String);
        final isWishlist = row['is_wishlist'] as bool? ?? false;
        if (cat == CollectionCategory.custom) {
          final sub = row['subcategory'] as String?;
          if (sub != null) {
            if (isWishlist) {
              // wishlist custom — ignore for tile badge for now
            } else {
              customCounts[sub] = (customCounts[sub] ?? 0) + 1;
            }
          }
          continue;
        }
        if (isWishlist) {
          wishCounts[cat] = (wishCounts[cat] ?? 0) + 1;
        } else {
          counts[cat] = (counts[cat] ?? 0) + 1;
        }
      }

      try {
        final groupIds = await CollectionItemScope.myGroupIds(userId);
        if (groupIds.isNotEmpty) {
          final gRows = await Supabase.instance.client
              .from('collection_items')
              .select('category, is_wishlist, is_sold, is_for_sale')
              .inFilter('group_id', groupIds);
          for (final row in gRows as List) {
            final isWishlist = row['is_wishlist'] as bool? ?? false;
            final isSold = row['is_sold'] as bool? ?? false;
            final isForSale = row['is_for_sale'] as bool? ?? false;
            if (isWishlist || isSold || isForSale) continue;
            final cat =
                CollectionCategory.fromDbValue(row['category'] as String);
            groupCounts[cat] = (groupCounts[cat] ?? 0) + 1;
          }
        }
      } catch (_) {
        // group_members RLS : compteurs perso OK, groupes ignorés
      }

      try {
        recommendationsList = await _recommendations.generate(limit: 6);
      } catch (_) {}

      orderedTiles = await loadVisibleHubTiles();
    } catch (e) {
      loadError = e.toString();
    }

    if (mounted) {
      setState(() {
        _counts = counts;
        _groupCounts = groupCounts;
        _wishlistCounts = wishCounts;
        _customCounts = customCounts;
        _orderedTiles = orderedTiles;
        _recommendationsList = recommendationsList;
        _loadingCounts = false;
      });
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

  void _openCategory(CollectionCategory category) {
    AppHaptics.selection();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => switch (category) {
          CollectionCategory.boardgame =>
            const BoardgamesCollectionScreen(),
          CollectionCategory.book => const BooksCollectionScreen(),
          CollectionCategory.card => const CardsCollectionScreen(),
          CollectionCategory.media => const MediaCollectionScreen(),
          CollectionCategory.lego => const LegoCollectionScreen(),
          CollectionCategory.watch => const WatchCollectionScreen(),
          CollectionCategory.videogame => const VideogameCollectionScreen(),
          CollectionCategory.movie => const MovieCollectionScreen(),
          CollectionCategory.wildlife => const WildlifeCollectionScreen(),
          CollectionCategory.restaurant => const RestaurantCollectionScreen(),
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
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Statistiques',
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
                      'Salut $_username',
                      style: greetingStyle?.copyWith(color: Colors.white),
                    ),
                  )
                else
                  Text(
                    'Salut $_username',
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
          if (!_loadingCounts && _recommendationsList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: RecommendationsBanner(items: _recommendationsList),
            ),
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

  Widget _buildCategoryCard(CollectionCategory category) {
    final count = _counts[category] ?? 0;
    final groupCount = _groupCounts[category] ?? 0;
    final wishCount = _wishlistCounts[category] ?? 0;
    final total = count + groupCount;
    final countLabel = category.countSummary(total);
    final wishLabel = wishCount > 0 ? '♥ $wishCount en wishlist' : null;

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
            Text(
              countLabel,
              style: TextStyle(fontSize: 12, color: category.color),
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
