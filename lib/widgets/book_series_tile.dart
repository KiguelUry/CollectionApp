import 'package:flutter/material.dart';

import '../constants/book_accent.dart';
import '../models/book_series.dart';
import 'collection_cover_image.dart';

class BookSeriesTile extends StatelessWidget {
  final BookSeries series;
  final BookSeriesStats stats;
  final VoidCallback onTap;
  final Color accent;

  const BookSeriesTile({
    super.key,
    required this.series,
    required this.stats,
    required this.onTap,
    this.accent = BookAccent.primary,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Cover(url: series.coverUrl),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            series.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          if (series.wishlistEntireSeries)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Wishlist série',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.tertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _Chip(
                    icon: Icons.library_books_outlined,
                    label: 'Possédé ${stats.ownedLabel}',
                    color: accent.withValues(alpha: 0.15),
                    iconColor: accent,
                  ),
                  _Chip(
                    icon: Icons.visibility_rounded,
                    label: 'Lu ${stats.readLabel}',
                    color: Colors.amber.withValues(alpha: 0.15),
                    iconColor: Colors.amber.shade800,
                  ),
                  if (stats.ratingLabel != null)
                    _Chip(
                      icon: Icons.star_rounded,
                      label: stats.ratingLabel!,
                      color: scheme.tertiaryContainer,
                      iconColor: scheme.onTertiaryContainer,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final String? url;

  const _Cover({this.url});

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    if (url != null && url!.isNotEmpty) {
      return CollectionCoverImage(
        url: url!,
        width: size,
        height: size * 1.45,
        bookCover: true,
      );
    }
    return _placeholder(size);
  }

  Widget _placeholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.auto_stories_outlined, color: Colors.white70),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }
}
