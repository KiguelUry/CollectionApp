import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../navigation/app_navigation.dart';
import '../theme/category_accent_theme.dart';
import 'category_collection_shell.dart';

/// En-tête compact coloré : retour, titre, onglets Collection/Wishlist, actions.
class CategoryCollectionHeader extends StatelessWidget {
  final CollectionCategory category;
  final String title;
  final TabController tabController;
  final Color? accentOverride;
  final List<CategoryQuickAction> quickActions;
  final List<Widget> extraActions;
  /// Après scroll : icônes seules ; au repos : pastilles avec libellé.
  final bool compactActions;

  const CategoryCollectionHeader({
    super.key,
    required this.category,
    required this.title,
    required this.tabController,
    this.accentOverride,
    this.quickActions = const [],
    this.extraActions = const [],
    this.compactActions = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentOverride ?? category.color;
    final onAccent = CategoryAccentTheme.onHeader(accent);
    final showCollectionsHome = !AppNavigation.isOnCollectionsHome(context);
    final hasToolbar = showCollectionsHome ||
        quickActions.isNotEmpty ||
        extraActions.isNotEmpty;
    final showLabels = !compactActions;
    final narrow = MediaQuery.sizeOf(context).width < 720;

    final leftActions = <_ToolbarAction>[
      if (showCollectionsHome)
        _ToolbarAction(
          tooltip: 'Accueil',
          label: 'Accueil',
          icon: Icons.home_rounded,
          color: onAccent,
          showLabel: showLabels,
          onTap: () => AppNavigation.openCollections(context),
        ),
      for (final action in quickActions)
        _ToolbarAction(
          tooltip: action.label,
          label: action.label,
          icon: action.icon,
          color: onAccent,
          showLabel: showLabels,
          onTap: action.onTap,
        ),
    ];

    return Material(
      child: Container(
        decoration: CategoryAccentTheme.headerDecoration(accent),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
                child: SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      if (Navigator.canPop(context))
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.arrow_back_rounded, color: onAccent),
                          onPressed: () => Navigator.maybePop(context),
                        )
                      else
                        const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: onAccent,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TabBar(
                controller: tabController,
                indicatorColor: onAccent,
                labelColor: onAccent,
                unselectedLabelColor: onAccent.withValues(alpha: 0.65),
                dividerColor: Colors.transparent,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                labelStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
                tabs: const [
                  Tab(height: 36, text: 'Collection'),
                  Tab(height: 36, text: 'Wishlist'),
                ],
              ),
              if (hasToolbar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 2, 4),
                  child: _ToolbarLayout(
                    leftActions: leftActions,
                    extraActions: extraActions,
                    twoRows: showLabels && narrow && leftActions.length >= 3,
                    compact: !showLabels,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarLayout extends StatelessWidget {
  final List<_ToolbarAction> leftActions;
  final List<Widget> extraActions;
  final bool twoRows;
  final bool compact;

  const _ToolbarLayout({
    required this.leftActions,
    required this.extraActions,
    required this.twoRows,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: extraActions,
    );

    if (!twoRows) {
      return SizedBox(
        height: compact ? 36 : 44,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: leftActions),
              ),
            ),
            trailing,
          ],
        ),
      );
    }

    // Mobile étiqueté : 2 lignes à gauche, toggles toujours visibles à droite.
    final mid = (leftActions.length / 2).ceil();
    final row1 = leftActions.take(mid).toList();
    final row2 = leftActions.skip(mid).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 40,
                child: Row(children: row1),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 40,
                child: Row(children: row2),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: trailing,
        ),
      ],
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  final String tooltip;
  final String label;
  final IconData icon;
  final Color color;
  final bool showLabel;
  final VoidCallback onTap;

  const _ToolbarAction({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.color,
    required this.showLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!showLabel) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      );
    }

    final short = _shortLabel(label);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      short,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
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

  static String _shortLabel(String label) {
    final t = label.trim();
    if (t.length <= 16) return t;
    final lower = t.toLowerCase();
    if (lower.contains('tirage')) return 'Tirage';
    if (lower.contains('parties')) return 'Parties';
    if (lower.contains('modif')) return 'Modifs';
    if (lower.contains('ajout')) return 'Ajouts';
    if (lower.contains('historique')) return 'Historique';
    return t;
  }
}
