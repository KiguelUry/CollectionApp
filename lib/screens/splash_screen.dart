import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/dev_auth_config.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
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

  Future<void> _navigateToNext() async {
    if (!DevAuthConfig.skipSplash) {
      await Future.delayed(const Duration(milliseconds: 4500));
    } else {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return;

    var session = Supabase.instance.client.auth.currentSession;

    if (session == null && DevAuthConfig.hasAutoLogin) {
      try {
        await AuthService().signIn(
          DevAuthConfig.testEmail!,
          DevAuthConfig.testPassword!,
        );
        session = Supabase.instance.client.auth.currentSession;
      } catch (e) {
        debugPrint('Connexion dev automatique échouée : $e');
      }
    }

    if (!mounted) return;

    if (session == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } else {
      try {
        await ProfileService().ensureCurrentUserProfile();
      } catch (e) {
        debugPrint('Profil utilisateur : $e');
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/categories');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (DevAuthConfig.skipSplash) {
      return Scaffold(
        backgroundColor: Colors.deepPurple.shade900,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                DevAuthConfig.hasAutoLogin
                    ? 'Connexion test…'
                    : 'Chargement…',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.deepPurple.shade900,
      body: Stack(
        alignment: Alignment.center,
        children: [
          ..._buildFlyingItems(),
          Center(
            child: Icon(Icons.shopping_bag, size: 100, color: Colors.red.shade400)
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
          Center(
            child: Text(
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
      final i = entry.key;
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
