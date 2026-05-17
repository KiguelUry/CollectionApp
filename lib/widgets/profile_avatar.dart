import 'package:flutter/material.dart';

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
            errorBuilder: (_, __, ___) => _initialCircle(accent, initial),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _initialCircle(
                accent,
                initial,
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return _initialCircle(accent, initial);
  }

  Widget _initialCircle(Color accent, String initial, {Widget? child}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: accent,
      child: child ??
          Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: radius * 0.85,
            ),
          ),
    );
  }
}
