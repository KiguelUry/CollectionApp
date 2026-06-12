import 'package:flutter/material.dart';

import '../utils/collection_grid_layout.dart';

import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';

/// Grille de types (cartes, vinyles…) — hub catalogue soigné.
class CategoryTypeHub extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<CategoryTypeHubItem> items;
  final CategoryTypeHubItem? featuredItem;
  final VoidCallback? onClassicList;
  final Color? accentColor;
  final Widget? header;
  /// Si false, le titre est déjà dans [CategoryHubHeader] — hero plus compact.
  final bool showTitleInHero;
  /// Icône décorative en filigrane dans le hero.
  final IconData? heroWatermark;

  const CategoryTypeHub({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    this.featuredItem,
    this.onClassicList,
    this.accentColor,
    this.header,
    this.showTitleInHero = true,
    this.heroWatermark,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentColor ?? scheme.primary;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            decoration: AppTheme.heroGradient(accent),
            child: Stack(
              children: [
                if (heroWatermark != null)
                  Positioned(
                    right: -8,
                    top: -12,
                    child: Icon(
                      heroWatermark,
                      size: 120,
                      color: accent.withValues(alpha: 0.12),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    showTitleInHero ? 8 : 4,
                    20,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showTitleInHero) ...[
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: showTitleInHero ? 14 : 13,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (header != null) ...[
                        SizedBox(height: showTitleInHero ? 16 : 12),
                        header!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (featuredItem != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _FeaturedTypeCard(item: featuredItem!, accent: accent),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, featuredItem != null ? 4 : 4, 16, 8),
          sliver: SliverGrid(
            gridDelegate: CollectionGridLayout.gridDelegate(
              context,
              mobileColumns: 2,
              childAspectRatio: 0.88,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _TypeCard(
                item: items[index],
                index: index,
              ),
              childCount: items.length,
            ),
          ),
        ),
        if (onClassicList != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              child: OutlinedButton.icon(
                onPressed: onClassicList,
                icon: const Icon(Icons.view_list_rounded),
                label: const Text('Voir toute la collection'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CategoryTypeHubItem {
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const CategoryTypeHubItem({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

/// Tuile pleine largeur en tête de hub (ex. « Toutes mes cartes »).
class _FeaturedTypeCard extends StatefulWidget {
  final CategoryTypeHubItem item;
  final Color accent;

  const _FeaturedTypeCard({required this.item, required this.accent});

  @override
  State<_FeaturedTypeCard> createState() => _FeaturedTypeCardState();
}

class _FeaturedTypeCardState extends State<_FeaturedTypeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: scheme.surfaceContainerLowest,
        elevation: _pressed ? 0 : 2,
        shadowColor: widget.accent.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: widget.accent.withValues(alpha: 0.28)),
        ),
        child: InkWell(
          onTap: () {
            AppHaptics.selection();
            widget.item.onTap();
          },
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.item.color.withValues(alpha: 0.24),
                        widget.item.color.withValues(alpha: 0.1),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.item.icon, size: 32, color: widget.item.color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.item.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 16, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatefulWidget {
  final CategoryTypeHubItem item;
  final int index;

  const _TypeCard({required this.item, required this.index});

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 8));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Material(
          color: scheme.surfaceContainerLowest,
          elevation: _pressed ? 0 : 1,
          shadowColor: widget.item.color.withValues(alpha: 0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: widget.item.color.withValues(alpha: 0.2),
            ),
          ),
          child: InkWell(
            onTap: () {
              AppHaptics.selection();
              widget.item.onTap();
            },
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                          widget.item.color.withValues(alpha: 0.22),
                          widget.item.color.withValues(alpha: 0.08),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.item.icon, size: 30, color: widget.item.color),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.item.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.item.description,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
