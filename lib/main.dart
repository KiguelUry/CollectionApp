import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/category_selection_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/groups_screen.dart';
import 'screens/profile_edit_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await SettingsService.instance.load();

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (supabaseUrl == null || supabaseAnonKey == null) {
    throw Exception(
      'Variables SUPABASE_URL et SUPABASE_ANON_KEY manquantes dans .env',
    );
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _settings = SettingsService.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_rebuild);
  }

  @override
  void dispose() {
    _settings.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Collectingo',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _settings.themeMode,
      home: const SplashScreen(),
      routes: {
        '/categories': (context) => const CategorySelectionScreen(),
        '/groups': (context) => const GroupsScreen(),
        '/friends': (context) => const FriendsScreen(),
        '/profile': (context) => const ProfileEditScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}
