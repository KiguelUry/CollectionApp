import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_completion_summary.dart';
import '../../services/lorcast_service.dart';
import '../../services/onepiece_tcg_service.dart';
import '../../services/riftscribe_service.dart';
import '../../services/scryfall_service.dart';
import '../../services/tcg_completion_service.dart';
import '../../services/ygoprodeck_service.dart';
import '../../widgets/app_app_bar.dart';
import 'pokemon_series_blocks_screen.dart';
import 'tcg_series_blocks_screen.dart';

/// Vue progression par univers TCG (données collection, sans quota API).
class TcgCompletionScreen extends StatefulWidget {
  const TcgCompletionScreen({super.key});

  @override
  State<TcgCompletionScreen> createState() => _TcgCompletionScreenState();
}

class _TcgCompletionScreenState extends State<TcgCompletionScreen> {
  final _service = TcgCompletionService();
  List<TcgSubcategoryStats> _stats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await _service.fetchSubcategoryStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCatalogBrowser(CardSubcategory sub) {
    if (sub == CardSubcategory.pokemon) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PokemonSeriesBlocksScreen()),
      );
      return;
    }
    final loadBlocks = switch (sub) {
      CardSubcategory.magic => ScryfallService.fetchBlocks,
      CardSubcategory.yugioh => YgoprodeckService.fetchBlocks,
      CardSubcategory.onepiece => OnepieceTcgService.fetchBlocks,
      CardSubcategory.lorcana => LorcastService.fetchBlocks,
      CardSubcategory.riftbound => RiftscribeService.fetchBlocks,
      _ => null,
    };
    if (loadBlocks == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TcgSeriesBlocksScreen(
          subcategory: sub,
          loadBlocks: loadBlocks,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalOwned =
        _stats.fold<int>(0, (sum, s) => sum + s.ownedCards);

    return Scaffold(
      appBar: const AppAppBar(title: 'Complétion TCG'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (totalOwned > 0)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$totalOwned cartes cataloguées',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Progression par set visible dans chaque extension '
                              '(badge possédé / total quand le catalogue le fournit).',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  for (final stat in _stats)
                    _SubcategoryCard(
                      stat: stat,
                      onBrowse: () => _openCatalogBrowser(stat.subcategory),
                    ),
                  if (_stats.every((s) => !s.hasCards))
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Ajoute des cartes depuis un catalogue pour voir ta progression ici.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SubcategoryCard extends StatelessWidget {
  final TcgSubcategoryStats stat;
  final VoidCallback onBrowse;

  const _SubcategoryCard({
    required this.stat,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final sub = stat.subcategory;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onBrowse,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: sub.color.withValues(alpha: 0.15),
                    child: Icon(sub.icon, size: 20, color: sub.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          stat.hasCards
                              ? '${stat.ownedCards} cartes · ${stat.setsTouched} série(s) touchée(s)'
                              : 'Aucune carte — parcourir le catalogue',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
              if (stat.topSets.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Sets les plus remplis',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final row in stat.topSets.take(5))
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${row.setName ?? row.setKey} · ${row.owned}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
