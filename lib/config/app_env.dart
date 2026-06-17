import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'supabase_public_config.dart';

/// Lit une variable `.env` avec repli sur [SupabasePublicConfig].
abstract final class AppEnv {
  /// Sur le web, URL figée (évite les fautes de frappe dans les secrets CI).
  static String get supabaseUrl {
    if (kIsWeb) return SupabasePublicConfig.url;
    final v = dotenv.env['SUPABASE_URL']?.trim();
    if (v != null && v.isNotEmpty) return _normalizeSupabaseUrl(v);
    return SupabasePublicConfig.url;
  }

  static String get supabaseAnonKey {
    final v = dotenv.env['SUPABASE_ANON_KEY']?.trim();
    if (v != null && v.isNotEmpty) return v;
    return SupabasePublicConfig.anonKey;
  }

  static String _normalizeSupabaseUrl(String url) {
    const correctHost = 'jfudrneoblsiingjqsio.supabase.co';
    if (url.contains(correctHost)) return url;
    // Corrige les typos fréquentes (lsling, qqslo…).
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.host.endsWith('.supabase.co')) return url;
    return Uri(
      scheme: uri.scheme,
      host: correctHost,
    ).toString();
  }
}
