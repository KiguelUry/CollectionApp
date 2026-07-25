import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/collection_item.dart';
import '../../services/boardgame_market_service.dart';
import '../../utils/wishlist_market_metadata.dart';

enum WishlistPriceFocus { secondhand, newPrice }

Future<void> showWishlistPriceSheet(
  BuildContext context, {
  required CollectionItem item,
  WishlistPriceFocus initialFocus = WishlistPriceFocus.secondhand,
  bool readOnly = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _WishlistPriceSheet(
      item: item,
      initialFocus: initialFocus,
      readOnly: readOnly,
    ),
  );
}

class _WishlistPriceSheet extends StatefulWidget {
  final CollectionItem item;
  final WishlistPriceFocus initialFocus;
  final bool readOnly;

  const _WishlistPriceSheet({
    required this.item,
    required this.initialFocus,
    required this.readOnly,
  });

  @override
  State<_WishlistPriceSheet> createState() => _WishlistPriceSheetState();
}

class _WishlistPriceSheetState extends State<_WishlistPriceSheet> {
  bool _refreshing = false;
  late CollectionItem _item;
  _HistoryRange _range = _HistoryRange.week;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  Future<void> _refreshPrices() async {
    setState(() => _refreshing = true);
    try {
      final bggId = _item.metadata?['bgg_id']?.toString();
      if (bggId == null || bggId.isEmpty) return;
      final patch = await BoardgameMarketService.fetchMarketPatch(
        bggId: bggId,
        existing: _item.metadata,
      );
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _item = _item.copyWith(
          metadata: mergeMarketMetadataPatch(_item.metadata, patch),
        );
      });
      await BoardgameMarketService.enrichItemMetadata(_item);
    } catch (_) {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final used = marketSecondhandPriceFromMetadata(_item.metadata);
    final neu = marketNewPriceMinFromMetadata(_item.metadata);
    final stores = storesPricesFromMetadata(_item.metadata);
    final history = marketHistoryFromMetadata(_item.metadata);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Comparateur de prix',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              if (!widget.readOnly) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _refreshing ? null : _refreshPrices,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: const Text('Actualiser'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _sectionTitle('Occasion (estimation)', Icons.recycling_rounded),
              const SizedBox(height: 6),
              _priceCard(
                label: 'Cote moyenne estimée',
                value: formatEuroChip(used, compact: false),
                hint:
                    'Estimation ~52 % du meilleur prix neuf constaté (BGG GeekMarket fermé). Compare avec Vinted, Leboncoin, etc.',
                accent: Colors.teal.shade700,
              ),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 10),
                SegmentedButton<_HistoryRange>(
                  segments: const [
                    ButtonSegment(
                      value: _HistoryRange.week,
                      label: Text('7 jours'),
                    ),
                    ButtonSegment(
                      value: _HistoryRange.month,
                      label: Text('1 mois'),
                    ),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) =>
                      setState(() => _range = s.first),
                ),
                const SizedBox(height: 8),
                _PriceSparkline(
                  points: _filterHistory(history),
                  range: _range,
                ),
              ],
              const SizedBox(height: 16),
              _sectionTitle('Neuf Europe', Icons.shopping_bag_outlined),
              const SizedBox(height: 6),
              if (neu != null)
                _priceCard(
                  label: 'Prix neuf minimum',
                  value: formatEuroChip(neu, compact: false),
                  hint: 'Meilleur prix produit en stock si disponible.',
                  accent: Colors.indigo.shade600,
                ),
              if (stores.isEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Pas de boutique en ligne trouvée pour ce jeu.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              BoardgameMarketService.vintedSearchUrl(_item.title),
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('Chercher sur Vinted'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              BoardgameMarketService.leboncoinSearchUrl(
                                _item.title,
                              ),
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('Leboncoin'),
                        ),
                      ],
                    ),
                  ],
                )
              else
                ...stores.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      tileColor: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      title: Text(
                        s.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          formatEuroChip(s.productEur ?? s.priceEur,
                              compact: false),
                          if (s.inStock) 'en stock' else 'hors stock',
                          if (s.country != null) s.country!,
                        ].join(' · '),
                      ),
                      trailing: s.url == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.open_in_new, size: 20),
                              onPressed: () => launchUrl(Uri.parse(s.url!)),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<MarketPriceHistoryPoint> _filterHistory(
    List<MarketPriceHistoryPoint> all,
  ) {
    final now = DateTime.now();
    final cutoff = _range == _HistoryRange.week
        ? now.subtract(const Duration(days: 7))
        : now.subtract(const Duration(days: 31));
    return all.where((p) => p.at != null && !p.at!.isBefore(cutoff)).toList();
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    );
  }

  Widget _priceCard({
    required String label,
    required String value,
    required String hint,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: accent)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(
              fontSize: 11,
              color: accent.withValues(alpha: 0.85),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

enum _HistoryRange { week, month }

class _PriceSparkline extends StatelessWidget {
  final List<MarketPriceHistoryPoint> points;
  final _HistoryRange range;

  const _PriceSparkline({required this.points, required this.range});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return Text(
        'Historique en cours de collecte (1 point par jour d’actualisation).',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    final values = points
        .map((p) => p.secondhandEur ?? p.newMinEur)
        .whereType<double>()
        .toList();
    if (values.length < 2) {
      return const SizedBox.shrink();
    }

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: CustomPaint(
            size: const Size(double.infinity, 56),
            painter: _SparklinePainter(
              values: values,
              color: Colors.teal.shade600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Min ${formatEuroChip(minV, compact: false)} · '
          'Moy ${formatEuroChip(avg, compact: false)} · '
          'Max ${formatEuroChip(maxV, compact: false)}',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs() < 0.01 ? 1.0 : maxV - minV;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final y = size.height - ((values[i] - minV) / span) * (size.height - 8) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}
