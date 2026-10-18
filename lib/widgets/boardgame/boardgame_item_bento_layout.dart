import 'package:flutter/material.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../../utils/app_page_route.dart';
import '../collection_cover_image.dart';
import '../cover_preview_sheet.dart';

/// Largeur max de la fiche jeu sur PC (grille Bento centrée).
const kBoardgameDetailMaxWidth = 920.0;

/// En-tête compact : couverture Hero, titre, catégorie, badges.
class BoardgameDetailCompactHeader extends StatelessWidget {
  final CollectionItem item;
  final List<Widget> badges;
  final String? expansionOfLabel;
  final Widget? belowTitle;

  const BoardgameDetailCompactHeader({
    super.key,
    required this.item,
    this.badges = const [],
    this.expansionOfLabel,
    this.belowTitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = item.category.color;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: item.imageUrl != null
              ? () => showCoverPreview(
                  context,
                  imageUrl: item.imageUrl,
                  title: item.title,
                )
              : null,
          child: Hero(
            tag: collectionCoverHeroTag(item.id),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: item.imageUrl != null
                  ? CollectionCoverImage(
                      url: item.imageUrl!,
                      width: 112,
                      height: 112,
                      boxedCover: true,
                      largeSource: true,
                      fit: BoxFit.contain,
                    )
                  : Container(
                      width: 112,
                      height: 112,
                      color: accent.withValues(alpha: 0.25),
                      child: Icon(item.category.icon, size: 40, color: accent),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (belowTitle != null) ...[
                const SizedBox(height: 6),
                belowTitle!,
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(CollectionCategory.boardgame.icon, size: 16),
                    label: Text(CollectionCategory.boardgame.label),
                  ),
                  if (item.isWishlist)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('Wishlist'),
                    ),
                  if (item.isOnLoan)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.swap_horiz, size: 16),
                      label: Text('Prêt · ${item.loaneeDisplayName}'),
                    ),
                  ...badges,
                ],
              ),
              if (expansionOfLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Extension de $expansionOfLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Grille 2 colonnes pour les tuiles Bento (s'adapte en 1 colonne sur mobile).
class BoardgameBentoGrid extends StatelessWidget {
  final List<Widget> children;

  const BoardgameBentoGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 560;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                children[i],
              ],
            ],
          );
        }
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: children,
        );
      },
    );
  }
}

/// Tuile synthétique ; un tap ouvre le détail complet en modal.
class BoardgameBentoSummaryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onOpenDetail;

  const BoardgameBentoSummaryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpenDetail,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 128,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: accent, size: 22),
                    const Spacer(),
                    Icon(Icons.open_in_full_rounded, size: 18, color: accent),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showBoardgameBentoDetailSheet(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Centre la fiche sur grands écrans.
class BoardgameDetailWidthLimiter extends StatelessWidget {
  final Widget child;

  const BoardgameDetailWidthLimiter({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kBoardgameDetailMaxWidth),
        child: child,
      ),
    );
  }
}
