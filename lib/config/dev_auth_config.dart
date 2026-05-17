import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Connexion rapide réservée au mode debug (`flutter run`, pas les builds release).
class DevAuthConfig {
  DevAuthConfig._();

  static bool get isActive => kDebugMode;

  static String? get testEmail {
    if (!isActive) return null;
    final v = dotenv.env['DEV_TEST_EMAIL']?.trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static String? get testPassword {
    if (!isActive) return null;
    final v = dotenv.env['DEV_TEST_PASSWORD']?.trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static bool get hasAutoLogin => testEmail != null && testPassword != null;

  /// Passe l'animation du splash (4,5 s) pendant les tests.
  static bool get skipSplash =>
      isActive && dotenv.env['DEV_SKIP_SPLASH']?.toLowerCase() == 'true';

  static String get loginButtonLabel =>
      dotenv.env['DEV_LOGIN_LABEL']?.trim().isNotEmpty == true
          ? dotenv.env['DEV_LOGIN_LABEL']!.trim()
          : 'Connexion test (dev)';
}
