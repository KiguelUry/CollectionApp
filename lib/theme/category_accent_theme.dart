import 'package:flutter/material.dart';

/// Dégradés contrastés pour en-têtes de collection (plus « filé » que la couleur plate).
abstract final class CategoryAccentTheme {
  static BoxDecoration headerDecoration(Color accent) {
    final deep = Color.lerp(accent, Colors.black, 0.28)!;
    final mid = accent;
    final light = Color.lerp(accent, Colors.white, 0.42)!;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [deep, mid, light],
        stops: const [0.0, 0.52, 1.0],
      ),
    );
  }

  static Color onHeader(Color accent) {
    final mid = accent;
    return mid.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
  }
}
