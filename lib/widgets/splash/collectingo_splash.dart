import 'package:flutter/material.dart';

import '../../config/app_brand.dart';

/// Splash Paloma : fond sombre élégant, titre net, sans audio.
class CollectingoSplash extends StatefulWidget {
  const CollectingoSplash({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 2200),
  });

  final VoidCallback onFinished;
  final Duration duration;

  @override
  State<CollectingoSplash> createState() => _CollectingoSplashState();
}

class _CollectingoSplashState extends State<CollectingoSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onFinished();
  }

  void _skip() {
    if (_done) return;
    _controller.stop();
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_controller.value);
            return DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0F1419),
                    Color(0xFF1B2838),
                    Color(0xFF243447),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
              child: SafeArea(
                child: Stack(
                  children: [
                    // Soft vignette
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, -0.15),
                            radius: 1.1,
                            colors: [
                              const Color(0xFFFFB74D).withValues(alpha: 0.08 * t),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Opacity(
                        opacity: ((t - 0.05) / 0.45).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DoveMark(progress: t),
                              const SizedBox(height: 28),
                              Text(
                                kAppDisplayName,
                                style: TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: Colors.white.withValues(
                                    alpha: 0.96,
                                  ),
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Tes collections, au même endroit',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.2,
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 28,
                      child: Opacity(
                        opacity: (t * 3 - 0.4).clamp(0.0, 0.7),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 100,
                              child: LinearProgressIndicator(
                                value: t,
                                backgroundColor: Colors.white12,
                                color: const Color(0xFFFFB74D),
                                borderRadius: BorderRadius.circular(4),
                                minHeight: 2.5,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Appuyer pour continuer',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Marque géométrique plate (colombe origami stylisée).
class _DoveMark extends StatelessWidget {
  const _DoveMark({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final scale = 0.82 + progress * 0.18;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: const Color(0xFF2A3A4D),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: CustomPaint(
          painter: _OrigamiDovePainter(
            color: PalomaBrand.cream,
            accent: const Color(0xFFFFB74D),
          ),
        ),
      ),
    );
  }
}

class _OrigamiDovePainter extends CustomPainter {
  _OrigamiDovePainter({required this.color, required this.accent});

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Paint()..color = color;
    final fold = Paint()..color = color.withValues(alpha: 0.72);
    final beak = Paint()..color = accent;

    // Wing
    final wing = Path()
      ..moveTo(w * 0.32, h * 0.48)
      ..lineTo(w * 0.58, h * 0.18)
      ..lineTo(w * 0.62, h * 0.52)
      ..close();
    canvas.drawPath(wing, fold);

    // Body
    final bodyPath = Path()
      ..moveTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.68, h * 0.38)
      ..lineTo(w * 0.55, h * 0.62)
      ..lineTo(w * 0.22, h * 0.78)
      ..close();
    canvas.drawPath(bodyPath, body);

    // Lower wing
    final wing2 = Path()
      ..moveTo(w * 0.36, h * 0.55)
      ..lineTo(w * 0.78, h * 0.58)
      ..lineTo(w * 0.48, h * 0.70)
      ..close();
    canvas.drawPath(wing2, fold);

    // Beak
    final beakPath = Path()
      ..moveTo(w * 0.66, h * 0.38)
      ..lineTo(w * 0.82, h * 0.34)
      ..lineTo(w * 0.68, h * 0.46)
      ..close();
    canvas.drawPath(beakPath, beak);

    // Eye
    canvas.drawCircle(
      Offset(w * 0.58, h * 0.42),
      w * 0.025,
      Paint()..color = const Color(0xFF1B2838),
    );
  }

  @override
  bool shouldRepaint(covariant _OrigamiDovePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.accent != accent;
}
