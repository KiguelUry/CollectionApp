import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/stats_dashboard.dart';

/// Vue d'ensemble « Bento » des statistiques (sans accès réseau).
class StatsDashboardView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
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
                  children: _kpis(context),
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
                if (data.hasValue || musicMarketValue > 0) ...[
                  const SizedBox(height: 20),
                  _ValueSection(data: data, musicMarketValue: musicMarketValue),
                ],
                if (data.topPlayed.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle('Top 3 des plus joués'),
                  const SizedBox(height: 8),
                  for (var i = 0; i < data.topPlayed.length; i++)
                    _RankedRow(
                      rank: i + 1,
                      item: data.topPlayed[i],
                      trailing: '${data.topPlayed[i].plays} '
                          '${data.topPlayed[i].plays > 1 ? 'parties' : 'partie'}',
                    ),
                ],
                ...footer,
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _kpis(BuildContext context) {
    final d = data;
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
        icon: Icons.local_shipping_outlined,
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
            width: 26,
            child: Text(
              '#$rank',
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
