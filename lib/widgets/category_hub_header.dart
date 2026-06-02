import 'package:flutter/material.dart';

import '../navigation/app_navigation.dart';
import '../theme/category_accent_theme.dart';

/// En-tête coloré pour les hubs (Livres, Cartes, Vinyles…) — sans AppBar blanc dupliqué.
class CategoryHubHeader extends StatelessWidget {
  final String title;
  final Color accentColor;
  final TabBar? tabBar;

  const CategoryHubHeader({
    super.key,
    required this.title,
    required this.accentColor,
    this.tabBar,
  });

  @override
  Widget build(BuildContext context) {
    final onAccent = CategoryAccentTheme.onHeader(accentColor);

    return Material(
      child: Container(
        decoration: CategoryAccentTheme.headerDecoration(accentColor),
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
                ],
              ),
            ),
            if (tabBar != null)
              TabBar(
                controller: tabBar!.controller,
                indicatorColor: onAccent,
                labelColor: onAccent,
                unselectedLabelColor: onAccent.withValues(alpha: 0.65),
                dividerColor: Colors.transparent,
                tabs: tabBar!.tabs,
              ),
          ],
        ),
      ),
      ),
    );
  }
}
