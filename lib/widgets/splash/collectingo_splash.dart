import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/collection_category.dart';
import '../../theme/app_theme.dart';

/// Splash « Collectingo » : icônes de collection en orbite, titre animé.
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
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(
                      const Color(0xFF1A1033),
                      AppTheme.seed,
                      t * 0.35,
                    )!,
                    Color.lerp(
                      const Color(0xFF2D1B4E),
                      const Color(0xFF7E57C2),
                      t * 0.5,
                    )!,
                    const Color(0xFFEDE7F6),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
              child: SafeArea(
                child: Stack(
                  children: [
                    ..._buildOrbitIcons(t),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoMark(t),
                          const SizedBox(height: 28),
                          _buildTitle(t),
                          const SizedBox(height: 10),
                          _buildTagline(t),
                        ],
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

  List<Widget> _buildOrbitIcons(double t) {
    final size = MediaQuery.sizeOf(context);
    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final radius = math.min(size.width, size.height) * 0.36;

    return List.generate(_orbitCategories.length, (i) {
      final cat = _orbitCategories[i];
      final angle =
          (i / _orbitCategories.length) * math.pi * 2 + t * math.pi * 0.85;
      final r = radius * (0.72 + 0.12 * math.sin(t * math.pi * 2 + i));
      final x = cx + math.cos(angle) * r;
      final y = cy + math.sin(angle) * r * 0.55;
      final iconT = ((t - i * 0.06) * 2.2).clamp(0.0, 1.0);
      final scale = 0.5 + iconT * 0.5;

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
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white30),
                boxShadow: [
                  BoxShadow(
                    color: cat.color.withValues(alpha: 0.35),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(cat.icon, color: Colors.white, size: 28),
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
            Icon(
              Icons.inventory_2_rounded,
              size: 44,
              color: AppTheme.seed.withValues(alpha: 0.9),
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
          child: const Text(
            'Collectingo',
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

  Widget _buildTagline(double t) {
    return Opacity(
      opacity: ((t - 0.35) / 0.45).clamp(0.0, 1.0),
      child: const Text(
        'Secoue. Collectionne. Joue.',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
