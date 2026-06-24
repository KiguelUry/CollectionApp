import 'package:flutter/material.dart';

import '../services/discogs_service.dart';

/// Bloc « Valeur du Marché » Discogs pour vinyles / CD.
class DiscogsMarketValueCard extends StatefulWidget {
  final String? releaseId;

  const DiscogsMarketValueCard({super.key, required this.releaseId});

  @override
  State<DiscogsMarketValueCard> createState() => _DiscogsMarketValueCardState();
}

class _DiscogsMarketValueCardState extends State<DiscogsMarketValueCard> {
  DiscogsMarketStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DiscogsMarketValueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.releaseId != widget.releaseId) _load();
  }

  Future<void> _load() async {
    final id = int.tryParse(widget.releaseId ?? '');
    if (id == null || !DiscogsService.isConfigured) {
      setState(() {
        _stats = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final stats = await DiscogsService.fetchMarketStats(id);
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DiscogsService.isConfigured) return const SizedBox.shrink();
    final releaseId = widget.releaseId;
    if (releaseId == null || releaseId.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final accent = Colors.teal.shade700;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: accent, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Valeur du marché',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'Argus Discogs',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_stats == null)
              Text(
                'Pas de données marché pour ce pressage.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              )
            else
              Row(
                children: [
                  _priceCell('Min', _stats!.format(_stats!.lowest), accent),
                  _priceCell('Médian', _stats!.format(_stats!.median), accent),
                  _priceCell('Max', _stats!.format(_stats!.highest), accent),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _priceCell(String label, String value, Color accent) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
