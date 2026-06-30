import 'package:flutter/material.dart';
import '../navigation/app_navigation.dart';
import 'item_title_text.dart';

/// Barre d'app standard : retour (si possible) + accueil Collections.
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool showCollectionsHome;
  final bool showBackButton;

  const AppAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.backgroundColor,
    this.foregroundColor,
    this.showCollectionsHome = true,
    this.showBackButton = true,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final onCollections = AppNavigation.isOnCollectionsHome(context);
    final canPop = Navigator.canPop(context);
    final showLeading = showBackButton && canPop;

    return AppBar(
      title: ItemTitleText(
        title: title,
        maxLines: 2,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
      ),
      bottom: bottom,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      automaticallyImplyLeading: showLeading,
      actions: [
        if (showCollectionsHome && !onCollections)
          IconButton(
            icon: const Icon(Icons.grid_view_rounded),
            tooltip: 'Collections',
            onPressed: () => AppNavigation.openCollections(context),
          ),
        ...?actions,
      ],
    );
  }
}
