import 'package:flutter/material.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/collection_stats_service.dart';
import '../widgets/bgg_network_image.dart';
import '../widgets/app_app_bar.dart';
import 'home_screen.dart';
import 'item_detail_screen.dart';

/// Tous les objets en wishlist, regroupés par catégorie.
class WishlistOverviewScreen extends StatefulWidget {
  const WishlistOverviewScreen({super.key});

  @override
  State<WishlistOverviewScreen> createState() => _WishlistOverviewScreenState();
}

class _WishlistOverviewScreenState extends State<WishlistOverviewScreen> {
  final _stats = CollectionStatsService();
  Map<CollectionCategory, List<CollectionItem>> _byCategory = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _byCategory = await _stats.fetchWishlistByCategory();
    } catch (_) {
      _byCategory = {};
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _total =>
      _byCategory.values.fold(0, (sum, list) => sum + list.length);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: 'Ma wishlist',
        actions: [
          if (_total > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  label: Text('$_total'),
                  backgroundColor: Colors.amber.shade100,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _byCategory.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Ta wishlist est vide',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ajoute un objet en cochant « Wishlist » lors de l\'ajout, ou depuis l\'onglet Wishlist d\'une catégorie.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      Card(
                        color: Colors.amber.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: Colors.amber.shade800,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Centralise ici tout ce que tu veux acquérir. Les alertes bon plan arriveront plus tard.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._byCategory.entries.map(_buildCategorySection),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCategorySection(
    MapEntry<CollectionCategory, List<CollectionItem>> entry,
  ) {
    final category = entry.key;
    final items = entry.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Icon(category.icon, color: category.color, size: 22),
              const SizedBox(width: 8),
              Text(
                category.label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${items.length}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => HomeScreen(category: category),
                  ),
                ).then((_) => _load()),
                child: const Text('Voir la catégorie'),
              ),
            ],
          ),
        ),
        ...items.map((item) => _buildWishlistTile(item, category)),
      ],
    );
  }

  Widget _buildWishlistTile(CollectionItem item, CollectionCategory category) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: item.imageUrl != null
                ? BggNetworkImage(url: item.imageUrl!)
                : ColoredBox(
                    color: category.color.withValues(alpha: 0.15),
                    child: Icon(category.icon, color: category.color),
                  ),
          ),
        ),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(item.listSubtitle ?? category.label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => ItemDetailScreen(item: item),
          ),
        ).then((_) => _load()),
      ),
    );
  }
}
