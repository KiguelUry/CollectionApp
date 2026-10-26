import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'supabase_public_config.dart';

/// Lit une variable : `--dart-define` → `.env` → [SupabasePublicConfig].
abstract final class AppEnv {
  static String get supabaseUrl {
    const fromDefine = String.fromEnvironment('SUPABASE_URL');
    if (fromDefine.trim().isNotEmpty) {
      return _normalizeSupabaseUrl(fromDefine.trim());
    }
    // Sur le web, URL figée (évite les fautes de frappe dans les secrets CI).
    if (kIsWeb) return SupabasePublicConfig.url;
    final v = _env('SUPABASE_URL');
    if (v != null && v.isNotEmpty) return _normalizeSupabaseUrl(v);
    return SupabasePublicConfig.url;
  }

  static String get supabaseAnonKey {
    const fromDefine = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();
    final v = _env('SUPABASE_ANON_KEY');
    if (v != null && v.isNotEmpty) return v;
    return SupabasePublicConfig.anonKey;
  }

  /// Clé Google Books : `--dart-define` puis `.env` (obligatoire en prod web).
  static String? get googleBooksApiKey {
    const fromDefine = String.fromEnvironment('GOOGLE_BOOKS_API_KEY');
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();
    final v = _env('GOOGLE_BOOKS_API_KEY');
    if (v != null && v.isNotEmpty) return v;
    return null;
  }

  static String? _env(String key) {
    try {
      final v = dotenv.env[key]?.trim();
      if (v == null || v.isEmpty) return null;
      return v;
    } catch (_) {
      return null;
    }
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
