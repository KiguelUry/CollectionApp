import 'package:flutter/material.dart';

import '../constants/rating_colors.dart';

/// Étoiles note personnelle (bleu métallique). Cycle : N → N−0.5 → effacer.
class StarRatingBar extends StatelessWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final int starCount;
  final Color? starColor;

  const StarRatingBar({
    super.key,
    required this.rating,
    required this.onChanged,
    this.starCount = 5,
    this.starColor,
  });

  void _onStarTap(int index) {
    final n = (index + 1).toDouble();
    final full = n;
    final half = n - 0.5;
    if ((rating - full).abs() < 0.05) {
      onChanged(half);
    } else if ((rating - half).abs() < 0.05) {
      onChanged(0);
    } else {
      onChanged(full);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = starColor ?? RatingColors.personal;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(starCount, (index) {
        final starValue = index + 1.0;
        final IconData icon;
        if (rating >= starValue - 0.01) {
          icon = Icons.star_rounded;
        } else if (rating >= starValue - 0.5 - 0.01) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }
        return IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: () => _onStarTap(index),
          icon: Icon(icon, color: color, size: 32),
        );
      }),
    );
  }
}
