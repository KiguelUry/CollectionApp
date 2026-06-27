import 'package:flutter/material.dart';

import '../utils/boardgame_display.dart';

/// Note moyenne BGG (communauté), affichée comme sur 5 étoiles.
class BggCommunityRatingPanel extends StatelessWidget {
  final double? avgRating;
  final bool loading;

  const BggCommunityRatingPanel({
    super.key,
    required this.avgRating,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final onFive = bggRatingOnFive(avgRating);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Note de la communauté',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 10),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (onFive == null)
          Text(
            'Note communautaire indisponible.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          Row(
            children: [
              ...List.generate(5, (i) {
                final filled = onFive >= i + 1;
                final half = !filled && onFive >= i + 0.5;
                return Icon(
                  half ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
                  size: 22,
                  color: Colors.amber.shade700,
                );
              }),
              const SizedBox(width: 10),
              Text(
                '${onFive.toStringAsFixed(1)} / 5',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (avgRating != null) ...[
                const SizedBox(width: 6),
                Text(
                  '(${avgRating!.toStringAsFixed(1)} BGG)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}
