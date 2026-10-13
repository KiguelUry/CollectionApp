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
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                tabs: const [
                  Tab(height: 36, text: 'Collection'),
                  Tab(height: 36, text: 'Wishlist'),
                ],
              ),
              if (hasToolbar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: SizedBox(
                    height: showLabels ? 44 : 36,
                    child: Row(
                      children: [
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
                        const Spacer(),
                        ...extraActions,
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
                    constraints: const BoxConstraints(maxWidth: 88),
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
    if (t.length <= 14) return t;
    // Libellés longs → version courte lisible.
    if (t.toLowerCase().contains('tirage')) return 'Tirage';
    if (t.toLowerCase().contains('parties')) return 'Parties';
    if (t.toLowerCase().contains('ajout')) return 'Ajouts';
    if (t.toLowerCase().contains('historique')) return 'Historique';
    return t;
  }
}
