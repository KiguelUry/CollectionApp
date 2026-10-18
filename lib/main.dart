import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/category_selection_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/groups_screen.dart';
import 'screens/friend_collection_screen.dart';
import 'services/profile_cache_service.dart';
import 'services/social_directory_cache.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'config/app_env.dart';
import 'config/app_brand.dart';
import 'services/settings_service.dart';
import 'navigation/app_route_observer.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Firefox vide les textures WebGL au scroll. Un cache plus grand évite
    // de jeter les jaquettes encore à l'écran ou juste au-dessus.
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = 2500;
    cache.maximumSizeBytes = 256 << 20;
  }

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Web/Vercel : assets/.env parfois absent ; repli AppEnv.
  }
  await initializeDateFormatting('fr_FR');

  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    anonKey: AppEnv.supabaseAnonKey,
  );

  // Après Supabase : SettingsService peut synchroniser le profil (ProfileService).
  await SettingsService.instance.load();
  if (Supabase.instance.client.auth.currentUser != null) {
    unawaited(SocialDirectoryCache.instance.warm());
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _settings = SettingsService.instance;
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_rebuild);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        unawaited(SocialDirectoryCache.instance.warm());
      }
      if (data.event == AuthChangeEvent.passwordRecovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/reset-password',
            (_) => false,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _settings.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: kAppDisplayName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _settings.themeMode,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [appRouteObserver],
      home: const SplashScreen(),
      routes: {
        '/categories': (context) => const CategorySelectionScreen(),
        '/groups': (context) => const GroupsScreen(),
        '/friends': (context) => const FriendsScreen(),
        '/profile': (context) => const _OwnProfileRoute(),
        '/settings': (context) => const SettingsScreen(),
        '/login': (context) => const LoginScreen(),
        '/reset-password': (context) => const ResetPasswordScreen(),
      },
    );
  }
}

class _OwnProfileRoute extends StatelessWidget {
  const _OwnProfileRoute();

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final profile = ProfileCacheService.instance.profile;
    if (uid == null) return const LoginScreen();
    return FriendCollectionScreen(
      profileId: uid,
      username: profile?.username ?? 'Moi',
      avatarUrl: profile?.avatarUrl,
      accentColor: profile?.accentColor,
      shareCollections: true,
    );
  }
}
