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

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(starCount, (index) {
        final starValue = index + 1.0;
        final filled = rating >= starValue - 0.25;
        return IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(
            rating == starValue ? starValue - 1.0 : starValue,
          ),
          icon: Icon(
            filled ? Icons.star : Icons.star_border,
            color: Colors.amber.shade700,
            size: 36,
          ),
        );
      }),
    );
  }
}
