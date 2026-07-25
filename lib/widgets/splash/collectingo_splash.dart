import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/app_brand.dart';
import '../../models/collection_category.dart';
import '../../theme/app_theme.dart';
import '../../utils/splash_audio.dart';

/// Splash Palomnia : icônes de collection en orbite, titre animé.
class CollectingoSplash extends StatefulWidget {
  const CollectingoSplash({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 6200),
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

  static const _orbitCategories = [
    CollectionCategory.boardgame,
    CollectionCategory.book,
    CollectionCategory.card,
    CollectionCategory.media,
    CollectionCategory.videogame,
    CollectionCategory.lego,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      })
      ..forward();
    SplashAudio.playStartup();
  }

  @override
  void dispose() {
    _controller.dispose();
    SplashAudio.dispose();
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
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(
                      const Color(0xFF0F2027),
                      const Color(0xFF203A43),
                      t,
                    )!,
                    Color.lerp(
                      const Color(0xFF2C5364),
                      const Color(0xFFFF6B6B),
                      t * 0.55,
                    )!,
                    Color.lerp(
                      const Color(0xFFFFE66D),
                      const Color(0xFFFFF8E7),
                      t * 0.85,
                    )!,
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
              child: SafeArea(
                child: Stack(
                  children: [
                    ..._buildParticles(t),
                    ..._buildOrbitIcons(t),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 22,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildLogoMark(t),
                            const SizedBox(height: 24),
                            _buildTitle(t),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 28,
                      child: Opacity(
                        opacity: (t * 4 - 0.5).clamp(0.0, 0.75),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 120,
                              child: LinearProgressIndicator(
                                value: t,
                                backgroundColor: Colors.white24,
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                minHeight: 3,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Appuyer pour continuer',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
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

  List<Widget> _buildParticles(double t) {
    final size = MediaQuery.sizeOf(context);
    return List.generate(18, (i) {
      final seed = i * 1.618;
      final x = (math.sin(seed * 3.1 + t * 2) * 0.5 + 0.5) * size.width;
      final y = (math.cos(seed * 2.7 + t * 1.6) * 0.5 + 0.5) * size.height;
      final s = 3.0 + (i % 4);
      return Positioned(
        left: x,
        top: y,
        child: Opacity(
          opacity: (0.15 + 0.35 * math.sin(t * math.pi + seed)).clamp(0.0, 0.5),
          child: Container(
            width: s,
            height: s,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    });
  }

  List<Widget> _buildOrbitIcons(double t) {
    final size = MediaQuery.sizeOf(context);
    final cx = size.width / 2;
    final cy = size.height * 0.38;
    final radius = math.min(size.width, size.height) * 0.44;

    return List.generate(_orbitCategories.length, (i) {
      final cat = _orbitCategories[i];
      final angle =
          (i / _orbitCategories.length) * math.pi * 2 + t * math.pi * 0.85;
      final r = radius * (0.88 + 0.08 * math.sin(t * math.pi * 2 + i));
      final x = cx + math.cos(angle) * r;
      final y = cy + math.sin(angle) * r * 0.52;
      final iconT = ((t - i * 0.06) * 2.2).clamp(0.0, 1.0);
      final scale = 0.52 + iconT * 0.48;

      return Positioned(
        left: x - 28,
        top: y - 28,
        child: Opacity(
          opacity: iconT,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cat.color.withValues(alpha: 0.55),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cat.color.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(cat.icon, color: cat.color, size: 28),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildLogoMark(double t) {
    final scale = 0.6 + t * 0.4;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.95),
              Colors.white.withValues(alpha: 0.75),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.seed.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: t * math.pi * 0.25,
              child: Icon(
                Icons.casino_rounded,
                size: 44,
                color: const Color(0xFF2C5364).withValues(alpha: 0.9),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: Icon(
                Icons.favorite_rounded,
                size: 18,
                color: Colors.pink.shade300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(double t) {
    final slide = (1 - t) * 24;
    return Transform.translate(
      offset: Offset(0, slide),
      child: Opacity(
        opacity: ((t - 0.15) / 0.5).clamp(0.0, 1.0),
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFFE1BEE7)],
          ).createShader(bounds),
          child: Text(
            kAppDisplayName,
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }
}
