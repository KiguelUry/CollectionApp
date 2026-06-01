import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../models/collection_summary.dart';
import '../services/collection_stats_service.dart';
import '../widgets/collapsible_collection_overview.dart';
import '../widgets/main_drawer.dart';
import 'books_collection_screen.dart';
import 'cards_collection_screen.dart';
import 'home_screen.dart';
import 'media_collection_screen.dart';
import 'stats_screen.dart';
import 'wishlist_overview_screen.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import '../utils/collection_item_scope.dart';

class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});

  @override
  State<CategorySelectionScreen> createState() =>
      _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  final _statsService = CollectionStatsService();
  Map<CollectionCategory, int> _counts = {};
  Map<CollectionCategory, int> _groupCounts = {};
  Map<CollectionCategory, int> _wishlistCounts = {};
  CollectionSummary _summary = const CollectionSummary();
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _getUsername() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 'Aventurier';

    final data = await Supabase.instance.client
        .from('profiles')
        .select('username')
        .eq('id', user.id)
        .single();
    return data['username'] ?? 'Aventurier';
  }

  Future<void> _load() async {
    setState(() => _loadingCounts = true);

    final counts = {
      for (final c in CollectionCategory.menuValues) c: 0,
    };
    final groupCounts = {
      for (final c in CollectionCategory.menuValues) c: 0,
    };
    final wishCounts = {
      for (final c in CollectionCategory.menuValues) c: 0,
    };
    CollectionSummary summary = const CollectionSummary();
    String? loadError;

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final rows = await CollectionItemScope.personal(
        Supabase.instance.client
            .from('collection_items')
            .select('category, is_wishlist'),
        userId: userId,
      );

      for (final row in rows as List) {
        final cat = CollectionCategory.fromDbValue(row['category'] as String);
        final isWishlist = row['is_wishlist'] as bool? ?? false;
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
        summary = await _statsService.fetchSummary();
      } catch (_) {}
    } catch (e) {
      loadError = e.toString();
    }

    if (mounted) {
      setState(() {
        _counts = counts;
        _groupCounts = groupCounts;
        _wishlistCounts = wishCounts;
        _summary = summary;
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
          CollectionCategory.book => const BooksCollectionScreen(),
          CollectionCategory.card => const CardsCollectionScreen(),
          CollectionCategory.media => const MediaCollectionScreen(),
          _ => HomeScreen(category: category),
        },
      ),
    ).then((_) => _load());
  }

  void _openWishlist() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => const WishlistOverviewScreen()),
    ).then((_) => _load());
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
            decoration: AppTheme.heroGradient(scheme.primary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String>(
                  future: _getUsername(),
                  builder: (context, snapshot) {
                    final name = snapshot.data ?? '...';
                    return Text(
                      'Salut $name',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    );
                  },
                ),
                Text(
                  'Quelle collection ouvrir ?',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (!_loadingCounts) ...[
                  const SizedBox(height: 10),
                  CollapsibleCollectionOverview(
                    summary: _summary,
                    onWishlistTap: _openWishlist,
                    onStatsTap: _openStats,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loadingCounts
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.88,
                    ),
                    itemCount: CollectionCategory.menuValues.length,
                    itemBuilder: (context, index) => _AnimatedCategoryCard(
                      index: index,
                      child: _buildCategoryCard(
                        CollectionCategory.menuValues[index],
                      ),
                    ),
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
