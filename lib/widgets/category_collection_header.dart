import 'package:flutter/foundation.dart' show kIsWeb;
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
  /// Petites icônes secondaires dans la ligne du titre (ex. Modifs).
  final List<CategoryQuickAction> titleActions;
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
    this.titleActions = const [],
    this.compactActions = false,
  });

  /// Hauteur hors SafeArea.top pour PreferredSize (titre + tabs + toolbar).
  static double contentHeight({
    required double maxWidth,
    required bool compact,
    required int quickActionCount,
    required bool hasToolbar,
  }) {
    const title = 40.0;
    const tabs = 36.0;
    if (!hasToolbar) return title + tabs + 2;
    final narrow = maxWidth < 720;
    final twoRows = !compact && narrow && quickActionCount >= 4;
    final toolbar = twoRows ? 92.0 : (compact ? 36.0 : 44.0);
    return title + tabs + toolbar + 6;
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentOverride ?? category.color;
    final onAccent = CategoryAccentTheme.onHeader(accent);
    final showCollectionsHome = !AppNavigation.isOnCollectionsHome(context);
    final hasToolbar = showCollectionsHome ||
        quickActions.isNotEmpty ||
        extraActions.isNotEmpty;
    final showLabels = !compactActions;

    final leftActions = <_ToolbarAction>[
      for (final action in quickActions)
        _ToolbarAction(
          tooltip: action.label,
          label: action.label,
          icon: action.icon,
          color: onAccent,
          showLabel: showLabels,
          showBadge: action.showBadge,
          onTap: action.onTap,
        ),
    ];
    return Material(
      child: Container(
        decoration: CategoryAccentTheme.headerDecoration(accent),
        // Sur web mobile le chrome navigateur gère déjà le haut : pas de SafeArea.top
        // (évite la bande verte vide au-dessus du titre).
        child: SafeArea(
          top: !kIsWeb,
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
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
                      for (final action in titleActions)
                        _ToolbarAction(
                          key: ValueKey('title_action_${action.label}'),
                          tooltip: action.label,
                          label: action.label,
                          icon: action.icon,
                          color: onAccent,
                          showLabel: false,
                          showBadge: action.showBadge,
                          onTap: action.onTap,
                        ),
                      // Accueil en haut à droite, au-dessus des toggles colonnes.
                      if (showCollectionsHome)
                        IconButton(
                          tooltip: 'Accueil',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.home_rounded, color: onAccent),
                          onPressed: () =>
                              AppNavigation.openCollections(context),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 720;
                      // Au scroll (compact) : toujours 1 seule ligne.
                      // Au repos sur mobile : 2 rangées si ≥ 4 actions.
                      return _ToolbarLayout(
                        leftActions: leftActions,
                        extraActions: extraActions,
                        twoRows:
                            showLabels && narrow && leftActions.length >= 4,
                        compact: !showLabels,
                      );
                    },
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
      // Au repos, ≤ 3 actions : rangée équilibrée (largeurs égales).
      final balanced = !compact && leftActions.length <= 3;
      return SizedBox(
        height: compact ? 36 : 44,
        child: Row(
          children: [
            Expanded(
              child: balanced
                  ? Row(
                      children: [
                        for (final a in leftActions)
                          Expanded(child: a.expanded()),
                      ],
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: leftActions),
                    ),
            ),
            trailing,
          ],
        ),
      );
    }

    // Écran étroit : 2 boutons au-dessus, 2 en dessous.
    final split = (leftActions.length / 2).ceil();
    final row1 = leftActions.take(split).toList();
    final row2 = leftActions.skip(split).toList();

    return SizedBox(
      height: 92,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 40, child: Row(children: row1)),
                if (row2.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SizedBox(height: 40, child: Row(children: row2)),
                ],
              ],
            ),
          ),
          trailing,
        ],
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
  final bool showBadge;
  final VoidCallback onTap;
  final bool fill;

  const _ToolbarAction({
    super.key,
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.color,
    required this.showLabel,
    required this.onTap,
    this.showBadge = false,
    this.fill = false,
  });

  _ToolbarAction expanded() => _ToolbarAction(
        key: key,
        tooltip: tooltip,
        label: label,
        icon: icon,
        color: color,
        showLabel: showLabel,
        onTap: onTap,
        showBadge: showBadge,
        fill: true,
      );

  Widget _iconWithBadge() {
    final iconWidget = Icon(icon, size: showLabel ? 18 : 22, color: color);
    if (!showBadge) return iconWidget;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        iconWidget,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

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
            child: _iconWithBadge(),
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
                mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconWithBadge(),
                  const SizedBox(width: 5),
                  if (fill) Flexible(child: _labelText(short)) else _labelText(short),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _labelText(String text) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 110),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: fill ? 12 : 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );

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
