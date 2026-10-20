import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/stats_dashboard.dart';

/// Vue d'ensemble « Bento » des statistiques (sans accès réseau).
class StatsDashboardView extends StatefulWidget {
  final StatsDashboard data;
  final double musicMarketValue;
  final List<Widget> footer;

  static const maxContentWidth = 900.0;

  const StatsDashboardView({
    super.key,
    required this.data,
    this.musicMarketValue = 0,
    this.footer = const [],
  });

  @override
  State<StatsDashboardView> createState() => _StatsDashboardViewState();
}

class _StatsDashboardViewState extends State<StatsDashboardView> {
  var _showAllPlayed = false;

  StatsDashboard get data => widget.data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: StatsDashboardView.maxContentWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Vue d\'ensemble',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _KpiGrid(
                  columns: wide ? 4 : 2,
                  children: _kpis(context, data),
                ),
                if (data.categories.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle('Par catégorie'),
                  const SizedBox(height: 8),
                  _CategoryBars(
                    bars: data.categories,
                    total: data.ownedCount,
                    columns: wide ? 2 : 1,
                  ),
                ],
                if (data.hasValue || widget.musicMarketValue > 0) ...[
                  const SizedBox(height: 20),
                  _ValueSection(
                    data: data,
                    musicMarketValue: widget.musicMarketValue,
                  ),
                ],
                if (data.topPlayed.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle('Top 5 des plus joués'),
                  const SizedBox(height: 8),
                  for (
                    var i = 0;
                    i <
                        (_showAllPlayed
                            ? data.topPlayed.length.clamp(0, 10)
                            : data.topPlayed.length.clamp(0, 5));
                    i++
                  )
                    _RankedRow(
                      rank: i + 1,
                      item: data.topPlayed[i],
                      trailing: '${data.topPlayed[i].plays} '
                          '${data.topPlayed[i].plays > 1 ? 'parties' : 'partie'}',
                    ),
                  if (data.topPlayed.length > 5)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _showAllPlayed = !_showAllPlayed),
                        child: Text(
                          _showAllPlayed
                              ? 'Afficher le top 5'
                              : 'Voir le top 10',
                        ),
                      ),
                    ),
                ],
                if (data.topRated.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle('Les mieux notés (toutes collections)'),
                  const SizedBox(height: 8),
                  for (var i = 0; i < data.topRated.length; i++)
                    _RankedRow(
                      rank: i + 1,
                      item: data.topRated[i],
                      trailing:
                          '${data.topRated[i].ratingScore?.toStringAsFixed(1) ?? '—'} / 10',
                    ),
                ],
                ...widget.footer,
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _kpis(BuildContext context, StatsDashboard d) {
    final hasGames = d.boardgameCount > 0;
    return [
      StatsKpiCard(
        key: const ValueKey('kpi_owned'),
        icon: Icons.inventory_2_outlined,
        accent: Colors.indigo,
        label: 'Objets possédés',
        value: '${d.ownedCount}',
        caption: d.expansionCount > 0
            ? '+ ${d.expansionCount} extension${d.expansionCount > 1 ? 's' : ''}'
            : 'Catégories actives',
      ),
      StatsKpiCard(
        key: const ValueKey('kpi_wishlist'),
        icon: Icons.favorite_border,
        accent: Colors.pink,
        label: 'Wishlist',
        value: '${d.wishlistCount}',
        caption: d.wishlistPricedCount > 0
            ? '≈ ${formatEuroAmount(d.wishlistValue)} estimés'
            : 'Aucun prix estimé',
      ),
      StatsKpiCard(
        key: const ValueKey('kpi_play_rate'),
        icon: Icons.casino_outlined,
        accent: Colors.orange,
        label: 'Taux de jeu',
        value: hasGames ? '${(d.playedShare * 100).round()} %' : '—',
        caption: hasGames
            ? 'Pile de la honte ${(d.unplayedShare * 100).round()} % · '
                '${d.totalPlays} partie${d.totalPlays > 1 ? 's' : ''}'
            : 'Aucun jeu de société',
      ),
      StatsKpiCard(
        key: const ValueKey('kpi_away'),
        icon: Icons.place_outlined,
        accent: Colors.teal,
        label: 'Hors de chez moi',
        value: '${d.awayCount}',
        caption: d.loanedCount > 0
            ? 'dont ${d.loanedCount} prêté${d.loanedCount > 1 ? 's' : ''}'
            : 'Aucun prêt en cours',
      ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;

  const _KpiGrid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

/// Carte KPI du dashboard.
class StatsKpiCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? caption;

  const StatsKpiCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: accent,
                height: 1.1,
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryBars extends StatelessWidget {
  final List<StatsCategoryBar> bars;
  final int total;
  final int columns;

  const _CategoryBars({
    required this.bars,
    required this.total,
    required this.columns,
  });

  @override
  Widget build(BuildContext context) {
    final maxCount = bars.fold<int>(0, (a, b) => math.max(a, b.count));
    const gap = 16.0;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 10,
          children: [
            for (final bar in bars)
              SizedBox(
                width: w,
                child: _CategoryBar(bar: bar, total: total, maxCount: maxCount),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final StatsCategoryBar bar;
  final int total;
  final int maxCount;

  const _CategoryBar({
    required this.bar,
    required this.total,
    required this.maxCount,
  });

  @override
  Widget build(BuildContext context) {
    final cat = bar.category;
    final pct = total == 0 ? 0 : (bar.count / total * 100).round();
    final fill = maxCount == 0 ? 0.0 : bar.count / maxCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(cat.icon, size: 16, color: cat.color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                cat.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${bar.count} · $pct %',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fill,
            minHeight: 6,
            backgroundColor: cat.color.withValues(alpha: 0.12),
            color: cat.color,
          ),
        ),
      ],
    );
  }
}

class _ValueSection extends StatelessWidget {
  final StatsDashboard data;
  final double musicMarketValue;

  const _ValueSection({required this.data, required this.musicMarketValue});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[
      if (data.purchaseValue > 0)
        '${formatEuroAmount(data.purchaseValue)} prix d\'achat',
      if (data.estimatedValue > 0)
        '${formatEuroAmount(data.estimatedValue)} estimés (marché BGG)',
      if (musicMarketValue > 0)
        '${formatEuroAmount(musicMarketValue)} Argus Discogs',
    ];
    final total = data.totalValue + musicMarketValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Valeur de la collection'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '≈ ${formatEuroAmount(total)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                parts.join(' · '),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (data.paidCopies > 0 || data.marketCopies > 0) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MoneyCard(
                  icon: Icons.receipt_long_outlined,
                  title: 'Payé',
                  amount: data.paidTotal,
                  caption:
                      '${data.paidCopies} exemplaire${data.paidCopies > 1 ? 's' : ''} avec prix',
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MoneyCard(
                  icon: Icons.trending_up_rounded,
                  title: 'Valeur marché',
                  amount: data.marketTotal,
                  caption:
                      '${data.marketCopies} exemplaire${data.marketCopies > 1 ? 's' : ''} estimé${data.marketCopies > 1 ? 's' : ''} (BGG)',
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          if (data.comparableCopies > 0) ...[
            const SizedBox(height: 6),
            Text(
              data.comparableMarket >= data.comparablePaid
                  ? 'Plus-value de ${formatEuroAmount(data.comparableMarket - data.comparablePaid)} sur ${data.comparableCopies} exemplaire${data.comparableCopies > 1 ? 's' : ''} qui ont un prix payé et une valeur marché.'
                  : 'Moins-value de ${formatEuroAmount(data.comparablePaid - data.comparableMarket)} sur ${data.comparableCopies} exemplaire${data.comparableCopies > 1 ? 's' : ''} qui ont un prix payé et une valeur marché.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
        if (data.topValued.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _SectionTitle('Pièces les plus valorisées'),
          const SizedBox(height: 8),
          for (var i = 0; i < data.topValued.length; i++)
            _RankedRow(
              rank: i + 1,
              item: data.topValued[i],
              trailing: formatEuroAmount(data.topValued[i].value),
              note: data.topValued[i].isEstimate ? 'estim.' : null,
            ),
        ],
      ],
    );
  }
}

class _MoneyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final double amount;
  final String caption;
  final Color color;

  const _MoneyCard({
    required this.icon,
    required this.title,
    required this.amount,
    required this.caption,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            formatEuroAmount(amount),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          Text(
            caption,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  final int rank;
  final StatsDashboardItem item;
  final String trailing;
  final String? note;

  const _RankedRow({
    required this.rank,
    required this.item,
    required this.trailing,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cat = item.category;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '#$rank',
              softWrap: false,
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(cat.icon, size: 18, color: cat.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                note!,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
          Text(trailing, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
