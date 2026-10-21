import 'package:flutter/material.dart';

import '../../config/app_brand.dart';

/// Splash Paloma : fond sombre, animation légère (60 FPS), sans audio.
class CollectingoSplash extends StatefulWidget {
  const CollectingoSplash({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 1800),
  });

  final VoidCallback onFinished;
  final Duration duration;

  @override
  State<CollectingoSplash> createState() => _CollectingoSplashState();
}

class _CollectingoSplashState extends State<CollectingoSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _rise;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      });
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _rise = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
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
        backgroundColor: const Color(0xFF1B2838),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0F1419),
                Color(0xFF1B2838),
                Color(0xFF243447),
              ],
            ),
          ),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fade.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, _rise.value),
                    child: child,
                  ),
                );
              },
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DoveMark(),
                    SizedBox(height: 28),
                    Text(
                      kAppDisplayName,
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Colors.white,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Tes collections, au même endroit',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.2,
                        color: Color(0x8CFFFFFF),
                      ),
                    ),
                    SizedBox(height: 48),
                    SizedBox(
                      width: 100,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white12,
                        color: Color(0xFFFFB74D),
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        minHeight: 2.5,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
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
          ),
        ),
      ),
    );
  }
}

class _DoveMark extends StatelessWidget {
  const _DoveMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: const Color(0xFF2A3A4D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      child: const CustomPaint(
        painter: _OrigamiDovePainter(),
      ),
    );
  }
}

class _OrigamiDovePainter extends CustomPainter {
  const _OrigamiDovePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Paint()..color = PalomaBrand.cream;
    final fold = Paint()..color = PalomaBrand.cream.withValues(alpha: 0.72);
    final beak = Paint()..color = const Color(0xFFFFB74D);

    canvas.drawPath(
      Path()
        ..moveTo(w * 0.32, h * 0.48)
        ..lineTo(w * 0.58, h * 0.18)
        ..lineTo(w * 0.62, h * 0.52)
        ..close(),
      fold,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.28, h * 0.52)
        ..lineTo(w * 0.68, h * 0.38)
        ..lineTo(w * 0.55, h * 0.62)
        ..lineTo(w * 0.22, h * 0.78)
        ..close(),
      body,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.36, h * 0.55)
        ..lineTo(w * 0.78, h * 0.58)
        ..lineTo(w * 0.48, h * 0.70)
        ..close(),
      fold,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.66, h * 0.38)
        ..lineTo(w * 0.82, h * 0.34)
        ..lineTo(w * 0.68, h * 0.46)
        ..close(),
      beak,
    );
    canvas.drawCircle(
      Offset(w * 0.58, h * 0.42),
      w * 0.025,
      Paint()..color = const Color(0xFF1B2838),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
