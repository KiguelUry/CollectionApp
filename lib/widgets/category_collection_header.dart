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

  const CategoryCollectionHeader({
    super.key,
    required this.category,
    required this.title,
    required this.tabController,
    this.accentOverride,
    this.quickActions = const [],
    this.extraActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentOverride ?? category.color;
    final onAccent = CategoryAccentTheme.onHeader(accent);
    final showCollectionsHome = !AppNavigation.isOnCollectionsHome(context);
    final hasToolbar = showCollectionsHome ||
        quickActions.isNotEmpty ||
        extraActions.isNotEmpty;

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
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                child: Row(
                  children: [
                    if (Navigator.canPop(context))
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded, color: onAccent),
                        onPressed: () => Navigator.maybePop(context),
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: onAccent,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: tabController,
                indicatorColor: onAccent,
                labelColor: onAccent,
                unselectedLabelColor: onAccent.withValues(alpha: 0.65),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Collection'),
                  Tab(text: 'Wishlist'),
                ],
              ),
              if (hasToolbar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Row(
                    children: [
                      if (showCollectionsHome)
                        _ToolbarIcon(
                          tooltip: 'Collections',
                          icon: Icons.grid_view_rounded,
                          color: onAccent,
                          onTap: () => AppNavigation.openCollections(context),
                        ),
                      for (final action in quickActions)
                        _ToolbarIcon(
                          tooltip: action.label,
                          icon: action.icon,
                          color: onAccent,
                          onTap: action.onTap,
                        ),
                      const Spacer(),
                      ...extraActions,
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ToolbarIcon({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
}
