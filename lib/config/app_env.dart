import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'supabase_public_config.dart';

/// Lit une variable `.env` avec repli sur [SupabasePublicConfig].
abstract final class AppEnv {
  static String get supabaseUrl {
    final v = dotenv.env['SUPABASE_URL']?.trim();
    if (v != null && v.isNotEmpty) return v;
    return SupabasePublicConfig.url;
  }

  static String get supabaseAnonKey {
    final v = dotenv.env['SUPABASE_ANON_KEY']?.trim();
    if (v != null && v.isNotEmpty) return v;
    return SupabasePublicConfig.anonKey;
  }
}
