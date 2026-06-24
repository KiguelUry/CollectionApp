import 'package:flutter/material.dart';

/// Avatar rétro géométrique dérivé du pseudo (si pas de photo).
class RetroAvatar extends StatelessWidget {
  final String seed;
  final String initial;
  final Color accent;
  final double radius;

  const RetroAvatar({
    super.key,
    required this.seed,
    required this.initial,
    required this.accent,
    this.radius = 24,
  });

  static List<Color> paletteForSeed(String seed, Color accent) {
    final hash = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    final palettes = [
      [const Color(0xFF6C63FF), const Color(0xFF3F3D56)],
      [const Color(0xFF00B894), const Color(0xFF006266)],
      [const Color(0xFFE17055), const Color(0xFF6C2A2A)],
      [const Color(0xFF0984E3), const Color(0xFF2D3436)],
      [accent, accent.withValues(alpha: 0.55)],
    ];
    return palettes[hash % palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = paletteForSeed(seed, accent);
    final size = radius * 2;
    final hash = seed.hashCode.abs();

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: CustomPaint(
          painter: _RetroAvatarPainter(
            colors: colors,
            initial: initial,
            pattern: hash % 4,
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: radius * 0.85,
                shadows: const [
                  Shadow(color: Colors.black26, blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetroAvatarPainter extends CustomPainter {
  final List<Color> colors;
  final String initial;
  final int pattern;

  _RetroAvatarPainter({
    required this.colors,
    required this.initial,
    required this.pattern,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();
    paint.shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    ).createShader(rect);
    canvas.drawRect(rect, paint);

    paint.shader = null;
    paint.color = Colors.white.withValues(alpha: 0.12);
    switch (pattern) {
      case 0:
        for (var i = 0; i < 4; i++) {
          canvas.drawRect(
            Rect.fromLTWH(i * size.width / 4, 0, size.width / 8, size.height),
            paint,
          );
        }
      case 1:
        canvas.drawCircle(
          Offset(size.width * 0.8, size.height * 0.2),
          size.width * 0.22,
          paint,
        );
        canvas.drawCircle(
          Offset(size.width * 0.2, size.height * 0.75),
          size.width * 0.18,
          paint,
        );
      case 2:
        for (var y = 0; y < 6; y++) {
          for (var x = 0; x < 6; x++) {
            if ((x + y) % 2 == 0) {
              canvas.drawRect(
                Rect.fromLTWH(
                  x * size.width / 6,
                  y * size.height / 6,
                  size.width / 6,
                  size.height / 6,
                ),
                paint,
              );
            }
          }
        }
      default:
        final path = Path()
          ..moveTo(0, size.height * 0.35)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height * 0.55)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RetroAvatarPainter oldDelegate) =>
      oldDelegate.pattern != pattern || oldDelegate.colors != colors;
}
