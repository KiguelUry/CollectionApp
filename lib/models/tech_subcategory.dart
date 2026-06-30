import 'package:flutter/material.dart';

/// Sous-univers High-Tech (audio, gaming, mobilité, TV).
enum TechSubcategory {
  audio,
  gaming,
  mobile,
  tvVideo;

  String get dbValue => switch (this) {
        TechSubcategory.tvVideo => 'tv_video',
        _ => name,
      };

  String get label => switch (this) {
        TechSubcategory.audio => 'Audio',
        TechSubcategory.gaming => 'Gaming & périphériques',
        TechSubcategory.mobile => 'GSM & mobilité',
        TechSubcategory.tvVideo => 'TV & vidéo',
      };

  String get description => switch (this) {
        TechSubcategory.audio =>
          'Casques, écouteurs, enceintes, platines',
        TechSubcategory.gaming =>
          'Consoles, manettes, VR, souris, claviers…',
        TechSubcategory.mobile =>
          'Smartphones, tablettes, montres connectées',
        TechSubcategory.tvVideo =>
          'TV OLED/QLED, projecteurs, box TV',
      };

  IconData get icon => switch (this) {
        TechSubcategory.audio => Icons.headphones_rounded,
        TechSubcategory.gaming => Icons.sports_esports_rounded,
        TechSubcategory.mobile => Icons.smartphone_rounded,
        TechSubcategory.tvVideo => Icons.tv_rounded,
      };

  Color get color => switch (this) {
        TechSubcategory.audio => const Color(0xFF5C6BC0),
        TechSubcategory.gaming => const Color(0xFF7B1FA2),
        TechSubcategory.mobile => const Color(0xFF00897B),
        TechSubcategory.tvVideo => const Color(0xFF1565C0),
      };

  static TechSubcategory fromDbValue(String? value) {
    if (value == null) return TechSubcategory.audio;
    return TechSubcategory.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => TechSubcategory.audio,
    );
  }
}
