import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/collection_item.dart';
import '../services/boardgame_market_service.dart';
import '../services/collection_refresh.dart';
import '../utils/item_copy_units.dart';
import '../utils/wishlist_market_metadata.dart';

/// Estimations marché d'un jeu possédé : jauge neuf / occasion / achat,
/// historique et boutiques. Charge les prix BGG à la demande.
class ItemMarketValuePanel extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final ValueChanged<CollectionItem>? onItemUpdated;

  const ItemMarketValuePanel({
    super.key,
    required this.item,
    this.readOnly = false,
    this.onItemUpdated,
  });

  @override
  State<ItemMarketValuePanel> createState() => _ItemMarketValuePanelState();
}

class _ItemMarketValuePanelState extends State<ItemMarketValuePanel> {
  bool _loading = false;
  String? _error;
  late CollectionItem _item;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    final fetchedAt = DateTime.tryParse(
      _item.metadata?[kMarketPricesFetchedAt]?.toString() ?? '',
    );
    final stale = fetchedAt == null ||
        DateTime.now().difference(fetchedAt) >=
            BoardgameMarketService.marketPricesTtl;
    if ((!_hasPrices || stale) && _bggId != null && !widget.readOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void didUpdateWidget(covariant ItemMarketValuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) _item = widget.item;
  }

  String? get _bggId {
    final id = _item.metadata?['bgg_id']?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  bool get _hasPrices =>
      marketSecondhandPriceFromMetadata(_item.metadata) != null ||
      marketNewPriceMinFromMetadata(_item.metadata) != null ||
      marketPriceAvgFromMetadata(_item.metadata) != null;

  Future<void> _refresh() async {
    final bggId = _bggId;
    if (bggId == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patch = await BoardgameMarketService.fetchMarketPatch(
        bggId: bggId,
        existing: _item.metadata,
        includeExpansionCount: false,
      );
      final row = await Supabase.instance.client
          .from('collection_items')
          .select('metadata')
          .eq('id', _item.id)
          .maybeSingle();
      final current = row?['metadata'] is Map
          ? Map<String, dynamic>.from(row!['metadata'] as Map)
          : _item.metadata;
      final meta = mergeMarketMetadataPatch(current, patch);
      await Supabase.instance.client
          .from('collection_items')
          .update({'metadata': meta})
          .eq('id', _item.id);
      CollectionRefresh.instance.bump();
      if (!mounted) return;
      setState(() => _item = _item.copyWith(metadata: meta));
      widget.onItemUpdated?.call(_item);
    } catch (_) {
      if (mounted) setState(() => _error = 'Prix indisponibles pour le moment.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Prix payés connus (par exemplaire si doublons).
  List<double> get _paidPrices {
    final prices = copyPurchasePricesFromRow(
      quantity: _item.quantity,
      purchasePrice: _item.purchasePrice,
      metadata: _item.metadata,
    );
    return [for (final p in prices) if (p != null && p > 0) p];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = _item.metadata;
    final storedStores = storesPricesFromMetadata(meta);
    final summary = BoardgameMarketService.summarizePositivePrices(
      storedStores.map((s) => s.productEur ?? s.priceEur),
    );
    final newMin = summary?.min ?? marketNewPriceMinFromMetadata(meta);
    final second = summary?.secondhand ?? marketSecondhandPriceFromMetadata(meta);
    final rangeMin = summary?.min ?? marketPriceMinFromMetadata(meta);
    final rangeAvg = summary?.avg ?? marketPriceAvgFromMetadata(meta);
    final rangeMax = summary?.max ?? marketPriceMaxFromMetadata(meta);
    final hasRange = rangeMin != null && rangeAvg != null && rangeMax != null;
    final paid = _paidPrices;
    final avgPaid =
        paid.isEmpty ? null : paid.reduce((a, b) => a + b) / paid.length;
    final fetchedAt = DateTime.tryParse(
      meta?[kMarketPricesFetchedAt]?.toString() ?? '',
    );

    if (_bggId == null) {
      return Text(
        'Pas de référence BoardGameGeek : estimation impossible.',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }

    if (!_hasPrices) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _loading
                  ? 'Recherche des prix…'
                  : (_error ?? 'Aucun prix trouvé pour ce jeu.'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          if (_loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (!widget.readOnly)
            TextButton(onPressed: _refresh, child: const Text('Réessayer')),
        ],
      );
    }

    final delta = (avgPaid != null && second != null) ? second - avgPaid : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Prix neuf constatés',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (hasRange) ...[
              Expanded(child: _Figure(label: 'Min', value: rangeMin, color: Colors.teal)),
              Expanded(
                child: _Figure(
                  label: 'Moyenne',
                  value: rangeAvg,
                  color: Colors.teal.shade800,
                  big: true,
                ),
              ),
              Expanded(child: _Figure(label: 'Max', value: rangeMax, color: Colors.indigo)),
            ] else
              Expanded(
                child: _Figure(label: 'Neuf dès', value: newMin, color: Colors.indigo, big: true),
              ),
            Expanded(
              child: _Figure(
                label: paid.length > 1 ? 'Payé (moy.)' : 'Payé',
                value: avgPaid,
                color: Colors.orange.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          color: Colors.teal.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Estimation seconde main (occasion)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatEuroChip(second, compact: false),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Colors.teal.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PriceGauge(
          newMin: hasRange ? rangeMax : newMin,
          secondhand: hasRange ? rangeMin : second,
          paid: hasRange ? rangeAvg : avgPaid,
          lowLabel: hasRange ? 'Min' : 'Occasion',
          highLabel: hasRange ? 'Max' : 'Neuf',
          paidLabel: hasRange ? 'Moy.' : 'Payé',
        ),
        if (delta != null) ...[
          const SizedBox(height: 8),
          Text(
            delta >= 0
                ? 'Ton exemplaire vaut environ ${formatEuroChip(delta, compact: false)} de plus que ce que tu l\'as payé.'
                : 'Ton exemplaire vaut environ ${formatEuroChip(-delta, compact: false)} de moins que ce que tu l\'as payé.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: delta >= 0 ? Colors.green.shade700 : scheme.error,
            ),
          ),
        ],
        const SizedBox(height: 8),
        _ShopSearchLinks(title: _item.title),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                [
                  'Estimation indicative (BoardGamePrices)',
                  if (fetchedAt != null)
                    'mise à jour ${_ago(fetchedAt)}',
                ].join(' · '),
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ),
            if (!widget.readOnly)
              _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Actualiser',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: _refresh,
                    ),
          ],
        ),
      ],
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return 'à l\'instant';
    if (d.inHours < 24) return 'il y a ${d.inHours} h';
    return 'il y a ${d.inDays} j';
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final double? value;
  final Color color;
  final bool big;

  const _Figure({
    required this.label,
    required this.value,
    required this.color,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          formatEuroChip(value, compact: false),
          style: TextStyle(
            fontSize: big ? 20 : 16,
            fontWeight: FontWeight.w900,
            color: value == null ? null : color,
          ),
        ),
      ],
    );
  }
}

/// Barre horizontale avec un repère par prix (neuf, occasion, payé).
class _PriceGauge extends StatelessWidget {
  final double? newMin;
  final double? secondhand;
  final double? paid;
  final String lowLabel;
  final String highLabel;
  final String paidLabel;

  const _PriceGauge({
    this.newMin,
    this.secondhand,
    this.paid,
    this.lowLabel = 'Occasion',
    this.highLabel = 'Neuf',
    this.paidLabel = 'Payé',
  });

  @override
  Widget build(BuildContext context) {
    final marks = <({double v, Color c, String l})>[
      if (secondhand != null) (v: secondhand!, c: Colors.teal, l: lowLabel),
      if (newMin != null) (v: newMin!, c: Colors.indigo, l: highLabel),
      if (paid != null) (v: paid!, c: Colors.orange.shade800, l: paidLabel),
    ];
    if (marks.length < 2) return const SizedBox.shrink();
    final lo = marks.map((m) => m.v).reduce((a, b) => a < b ? a : b) * 0.85;
    final hi = marks.map((m) => m.v).reduce((a, b) => a > b ? a : b) * 1.1;
    final span = (hi - lo).abs() < 0.01 ? 1.0 : hi - lo;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 8,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: [
                        Colors.teal.withValues(alpha: 0.25),
                        Colors.indigo.withValues(alpha: 0.25),
                      ],
                    ),
                  ),
                ),
              ),
              for (final m in marks)
                Positioned(
                  left: ((m.v - lo) / span * w).clamp(0, w - 2) - 6,
                  top: 0,
                  child: Column(
                    children: [
                      Container(
                        width: 12,
                        height: 22,
                        decoration: BoxDecoration(
                          color: m.c,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Wrap(
                  spacing: 10,
                  children: [
                    for (final m in marks)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: m.c,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(m.l, style: const TextStyle(fontSize: 9)),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShopSearchLinks extends StatelessWidget {
  final String title;

  const _ShopSearchLinks({required this.title});

  @override
  Widget build(BuildContext context) {
    final shops = <(String, String)>[
      ('Le Zèbre à Pois', BoardgameMarketService.zebreAPoisSearchUrl(title)),
      ('Philibert', BoardgameMarketService.philibertSearchUrl(title)),
      (
        'Maison du Cormoran',
        BoardgameMarketService.maisonDuCormoranSearchUrl(title),
      ),
      ('Case Départ', BoardgameMarketService.caseDepartSearchUrl(title)),
      ('Ludum', BoardgameMarketService.ludumSearchUrl(title)),
      ('Cultura', BoardgameMarketService.culturaSearchUrl(title)),
      ('Fnac', BoardgameMarketService.fnacSearchUrl(title)),
      ('Amazon', BoardgameMarketService.amazonFrSearchUrl(title)),
    ];
    final second = <(String, String)>[
      ('Vinted', BoardgameMarketService.vintedSearchUrl(title)),
      ('Okkazeo', BoardgameMarketService.okkazeoSearchUrl(title)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Neuf', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final s in shops) _link(s.$1, s.$2)],
        ),
        const SizedBox(height: 8),
        Text('Seconde main', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final s in second) _link(s.$1, s.$2)],
        ),
      ],
    );
  }

  Widget _link(String label, String url) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.open_in_new, size: 16),
      onPressed: () => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}
