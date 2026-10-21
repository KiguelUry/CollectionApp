import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/dev_auth_config.dart';
import '../services/auth_service.dart';
import '../services/profile_cache_service.dart';
import '../services/profile_service.dart';
import '../services/social_directory_cache.dart';
import '../utils/hub_greeting.dart';
import '../widgets/profile/own_profile_panel.dart';
import '../widgets/splash/collectingo_splash.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    if (DevAuthConfig.skipSplash) {
      _navigateToNext();
    }
  }

  Future<void> _navigateToNext() async {
    if (_navigating) return;
    _navigating = true;

    if (!mounted) return;

    var session = Supabase.instance.client.auth.currentSession;

    // Connexion auto uniquement en mode dev rapide (pas après le splash normal).
    if (session == null &&
        DevAuthConfig.fastStart &&
        DevAuthConfig.hasAutoLogin) {
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
        final profileService = ProfileService();
        await profileService.ensureCurrentUserProfile();
        await ProfileCacheService.instance.hydrate();
        await ProfileCacheService.instance.refresh();
        OwnProfilePanel.memory = ProfileCacheService.instance.profile;
        // Genre + accord des salutations en mémoire avant le Hub / Profil.
        await preloadGreetingProfile(
          remoteFetch: profileService.fetchGreetingProfile,
        );
        unawaited(SocialDirectoryCache.instance.warm());
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
        backgroundColor: const Color(0xFF1B2838),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFFB74D)),
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

    return CollectingoSplash(onFinished: _navigateToNext);
  }
}
