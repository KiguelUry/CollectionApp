import 'package:flutter/material.dart';

class StarRatingBar extends StatelessWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final int starCount;

  const StarRatingBar({
    super.key,
    required this.rating,
    required this.onChanged,
    this.starCount = 5,
  });

  void _onStarTap(int index) {
    final starValue = index + 1.0;
    if ((rating - starValue).abs() < 0.01) {
      onChanged(starValue - 0.5);
    } else if ((rating - (starValue - 0.5)).abs() < 0.01) {
      onChanged(starValue);
    } else {
      onChanged(starValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(starCount, (index) {
        final starValue = index + 1.0;
        final IconData icon;
        if (rating >= starValue - 0.01) {
          icon = Icons.star;
        } else if (rating >= starValue - 0.5 - 0.01) {
          icon = Icons.star_half;
        } else {
          icon = Icons.star_border;
        }
        return IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: () => _onStarTap(index),
          icon: Icon(
            icon,
            color: Colors.amber.shade700,
            size: 36,
          ),
        );
      }),
    );
  }
}
