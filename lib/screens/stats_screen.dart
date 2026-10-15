import 'package:flutter/material.dart';

import '../services/collection_stats_service.dart';
import '../services/recommendation_service.dart';
import '../utils/stats_dashboard.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/recommendations_banner.dart';
import '../widgets/share_collection_sheet.dart';
import '../widgets/stats/stats_dashboard_view.dart';

/// Statistiques et export de la collection.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _stats = CollectionStatsService();

  StatsDashboard _dashboard = const StatsDashboard();
  double _musicMarketValue = 0;
  List<Recommendation> _recommendations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dashboard = await _stats.fetchDashboard();
      if (mounted) {
        setState(() {
          _dashboard = dashboard;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      final music = await _stats
          .fetchMusicMarketValueEstimate()
          .timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _musicMarketValue = music);
    } catch (_) {}
    try {
      final recs = await RecommendationService()
          .generate(limit: 5)
          .timeout(const Duration(seconds: 12));
      if (mounted) setState(() => _recommendations = recs);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Statistiques'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: StatsDashboardView(
                data: _dashboard,
                musicMarketValue: _musicMarketValue,
                footer: [
                  const SizedBox(height: 20),
                  if (_recommendations.isNotEmpty) ...[
                    RecommendationsBanner(items: _recommendations),
                    const SizedBox(height: 12),
                  ],
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
                ],
              ),
            ),
    );
  }
}
