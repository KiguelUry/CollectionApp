import 'package:flutter/material.dart';

import '../constants/book_accent.dart';
import '../models/book_series.dart';
import '../utils/tile_rating_display.dart';
import 'collection_cover_image.dart';
import 'item_title_text.dart';

/// Tuile série livres — même langage vertical que les jeux de société.
class BookSeriesTile extends StatelessWidget {
  final BookSeries series;
  final BookSeriesStats stats;
  final VoidCallback onTap;
  final Color accent;
  final VoidCallback? onDelete;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  const BookSeriesTile({
    super.key,
    required this.series,
    required this.stats,
    required this.onTap,
    this.accent = BookAccent.primary,
    this.onDelete,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Manga/BD/Comics ne sont jamais « Œuvre unique » (voir BookSeries.isStandalone).
    final isOneShot = series.isStandalone;
    final subLabel = isOneShot
        ? '${series.subcategory.label} · Œuvre unique'
        : '${series.subcategory.label} · ${stats.totalSlots} tomes';
    final ownedColor = stats.isComplete ? Colors.green.shade700 : accent;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: series.coverUrl != null &&
                              series.coverUrl!.trim().isNotEmpty
                          ? CollectionCoverImage(
                              url: series.coverUrl!,
                              bookCover: true,
                              boxedCover: true,
                              compact: true,
                              fit: BoxFit.contain,
                            )
                          : CoverImagePlaceholder(
                              bookCover: true,
                            ),
                    ),
                    if (onToggleFavorite != null)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: onToggleFavorite,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 15,
                                color: isFavorite
                                    ? Colors.redAccent
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (onDelete != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: onDelete,
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              ItemTitleText(
                title: series.name,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  height: 1.15,
                ),
              ),
              Text(
                subLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!isOneShot && stats.totalSlots > 0) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: stats.ownedProgress,
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: stats.isComplete
                        ? Colors.green.shade600
                        : const Color(0xFF26A69A),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              if (isOneShot)
                _MetaRow(
                  children: [
                    _MetaChip(
                      icon: Icons.menu_book_outlined,
                      label: stats.ownedCount > 0 ? 'Possédé' : 'Manquant',
                      color: stats.ownedCount > 0
                          ? Colors.green.shade700
                          : Colors.grey,
                    ),
                    _MetaChip(
                      icon: Icons.visibility_outlined,
                      label: stats.readCount > 0 ? 'Lu' : 'À lire',
                      color: stats.readCount > 0
                          ? Colors.amber.shade800
                          : Colors.blueGrey,
                    ),
                  ],
                )
              else ...[
                _MetaRow(
                  children: [
                    _MetaChip(
                      icon: Icons.menu_book_outlined,
                      label: stats.ownedLabel,
                      color: ownedColor,
                    ),
                    _MetaChip(
                      icon: Icons.visibility_outlined,
                      label: stats.readLabel,
                      color: Colors.amber.shade800,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Builder(
                  builder: (context) {
                    final chip = resolveTileRating(
                      personalOnFive: stats.displayRating,
                      communityOnFive: stats.communityRating,
                    );
                    return _MetaRow(
                      children: [
                        _MetaChip(
                          icon: Icons.star_rounded,
                          label: chip.label.replaceFirst('★ ', ''),
                          color: chip.color,
                        ),
                        _MetaChip(
                          icon: stats.valueLabel != null
                              ? Icons.payments_outlined
                              : Icons.place_outlined,
                          label: stats.valueLabel ?? '—',
                          color: Colors.teal.shade600,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final List<Widget> children;

  const _MetaRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
