import 'package:flutter/material.dart';

import '../constants/book_accent.dart';

/// Cellule « + » en fin de grille pour ajouter un tome manuel.
class BookVolumeAddCell extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const BookVolumeAddCell({
    super.key,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BookAccent.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 40, color: accent),
              const SizedBox(height: 6),
              Text(
                'Ajouter',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: accent,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
