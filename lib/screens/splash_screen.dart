import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'category_selection_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  void _navigateToNext() async {
    // Durée totale de l'animation avant de changer d'écran
    await Future.delayed(const Duration(milliseconds: 4500));
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            session == null
                ? const LoginScreen()
                : const CategorySelectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple.shade900,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Les objets qui volent vers le sac
          ..._buildFlyingItems(),

          // 2. Le Sac (La Hotte)
          Center(
            child:
                Icon(Icons.shopping_bag, size: 100, color: Colors.red.shade400)
                    .animate(
                      onPlay: (controller) => controller.repeat(reverse: true),
                    )
                    .shake(hz: 2, curve: Curves.easeInOut)
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.1, 1.1),
                      duration: 600.ms,
                    )
                    .then(delay: 3000.ms)
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(20, 20),
                      duration: 500.ms,
                      curve: Curves.easeInExpo,
                    )
                    .fadeOut(),
          ),

          // 3. Le Nom de l'App qui apparaît après l'explosion
          Center(
            child:
                Text(
                      "Collection\nFamille",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(color: Colors.orange.shade300, blurRadius: 20),
                        ],
                      ),
                    )
                    .animate()
                    .hide()
                    .then(delay: 3300.ms)
                    .show()
                    .scale(
                      begin: const Offset(0.2, 0.2),
                      end: const Offset(1, 1),
                      duration: 800.ms,
                      curve: Curves.easeOutBack,
                    )
                    .shimmer(duration: 1500.ms, color: Colors.orange.shade200)
                    .blurXY(begin: 10, end: 0, duration: 500.ms),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFlyingItems() {
    final icons = [
      Icons.casino,
      Icons.book,
      Icons.movie,
      Icons.sports_esports,
      Icons.music_note,
    ];
    return icons.asMap().entries.map((entry) {
      int i = entry.key;
      return Icon(entry.value, color: Colors.white70, size: 30)
          .animate()
          .move(
            begin: Offset(i % 2 == 0 ? -200 : 200, i < 2 ? -400 : 400),
            end: const Offset(0, 0),
            duration: (1000 + (i * 300)).ms,
            curve: Curves.easeIn,
          )
          .scale(begin: const Offset(1, 1), end: const Offset(0, 0))
          .fadeOut(delay: (800 + (i * 300)).ms);
    }).toList();
  }
}
