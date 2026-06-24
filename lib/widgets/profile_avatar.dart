import 'package:flutter/material.dart';

import 'profile/retro_avatar.dart';

/// Avatar utilisateur (photo ou initiale sur fond coloré).
class ProfileAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? accentColorHex;
  final String fallbackInitial;
  final double radius;

  const ProfileAvatar({
    super.key,
    this.avatarUrl,
    this.accentColorHex,
    required this.fallbackInitial,
    this.radius = 24,
  });

  static Color colorFromHex(String? hex, {Color fallback = Colors.deepPurple}) {
    if (hex == null || hex.isEmpty) return fallback;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return fallback;
    return Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = colorFromHex(accentColorHex);
    final initial = fallbackInitial.isNotEmpty
        ? fallbackInitial[0].toUpperCase()
        : '?';

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Image.network(
            avatarUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => RetroAvatar(
              seed: fallbackInitial,
              initial: initial,
              accent: accent,
              radius: radius,
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return RetroAvatar(
                seed: fallbackInitial,
                initial: initial,
                accent: accent,
                radius: radius,
              );
            },
          ),
        ),
      );
    }

    return RetroAvatar(
      seed: fallbackInitial,
      initial: initial,
      accent: accent,
      radius: radius,
    );
  }
}
