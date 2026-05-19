import 'package:flutter/material.dart';
import '../models/category_stat.dart';
import '../models/collection_item.dart';
import '../models/collection_summary.dart';
import '../services/collection_stats_service.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/share_collection_sheet.dart';

/// Statistiques et export de la collection.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _stats = CollectionStatsService();

  CollectionSummary _summary = const CollectionSummary();
  List<CategoryStat> _byCategory = [];
  List<CollectionItem> _topItems = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _stats.fetchSummary(),
        _stats.fetchCategoryStats(),
        _stats.fetchTopValuedItems(),
      ]);
      _summary = results[0] as CollectionSummary;
      _byCategory = results[1] as List<CategoryStat>;
      _topItems = results[2] as List<CollectionItem>;
    } catch (_) {
      _byCategory = [];
      _topItems = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const AppAppBar(title: 'Statistiques'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vue d\'ensemble',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _metricRow(
                            'Objets possédés',
                            '${_summary.ownedCount}',
                          ),
                          _metricRow(
                            'Wishlist',
                            '${_summary.wishlistCount}',
                          ),
                          _metricRow(
                            'Valeur indicative',
                            _summary.hasAnyValue
                                ? '${_summary.totalPurchaseValue.toStringAsFixed(2)} €'
                                : '—',
                            subtitle: _summary.hasAnyValue
                                ? '${_summary.pricedItemCount} fiche(s) avec prix d\'achat'
                                : 'Renseigne des prix d\'achat sur tes fiches',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => showShareCollectionSheet(context),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Partager ma collection'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Résumé lisible pour tes proches, CSV pour l\'assurance, ou copie sur PC.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Par catégorie',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_byCategory.isEmpty)
                    const Text('Aucune donnée pour l\'instant.')
                  else
                    ..._byCategory.map(_buildCategoryBar),
                  const SizedBox(height: 20),
                  Text(
                    'Pièces les plus valorisées (achat)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_topItems.isEmpty)
                    Text(
                      'Ajoute des prix d\'achat pour voir un classement.',
                      style: TextStyle(color: Colors.grey.shade600),
                    )
                  else
                    ..._topItems.map((item) {
                      final total =
                          (item.purchasePrice ?? 0) * item.quantity;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                item.category.color.withValues(alpha: 0.15),
                            child: Icon(
                              item.category.icon,
                              color: item.category.color,
                              size: 22,
                            ),
                          ),
                          title: Text(item.title, maxLines: 1),
                          subtitle: Text(item.category.label),
                          trailing: Text(
                            '${total.toStringAsFixed(0)} €',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _metricRow(String label, String value, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(CategoryStat stat) {
    final total = _summary.ownedCount;
    final pct = (stat.shareOf(total) * 100).clamp(0, 100);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(stat.category.icon, size: 18, color: stat.category.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stat.category.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${stat.itemCount} · ${pct.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : stat.itemCount / total,
              minHeight: 8,
              backgroundColor: stat.category.color.withValues(alpha: 0.12),
              color: stat.category.color,
            ),
          ),
          if (stat.purchaseValue > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '~${stat.purchaseValue.toStringAsFixed(0)} € (achat)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}
