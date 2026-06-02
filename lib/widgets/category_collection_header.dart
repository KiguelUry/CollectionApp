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
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  if (Navigator.canPop(context))
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: onAccent),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: onAccent,
                      ),
                    ),
                  ),
                  if (!AppNavigation.isOnCollectionsHome(context))
                    IconButton(
                      tooltip: 'Collections',
                      icon: Icon(Icons.grid_view_rounded, color: onAccent),
                      onPressed: () => AppNavigation.openCollections(context),
                    ),
                  ...extraActions,
                ],
              ),
            ),
            if (quickActions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < quickActions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        _QuickIcon(
                          action: quickActions[i],
                          color: onAccent,
                        ),
                      ],
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
              tabs: const [
                Tab(text: 'Collection'),
                Tab(text: 'Wishlist'),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _QuickIcon extends StatelessWidget {
  final CategoryQuickAction action;
  final Color color;

  const _QuickIcon({
    required this.action,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.label,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(action.icon, size: 22, color: color),
        ),
      ),
    );
  }
}
