import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Connexion rapide réservée au mode debug (`flutter run`, pas les builds release).
class DevAuthConfig {
  DevAuthConfig._();

  static bool get isActive => kDebugMode;

  /// Lit `--dart-define=KEY=true` puis `.env` (dart-define prioritaire).
  static bool _envFlag(String key) {
    final fromDefine = String.fromEnvironment(key);
    if (fromDefine.isNotEmpty) {
      return fromDefine.toLowerCase() == 'true';
    }
    return dotenv.env[key]?.toLowerCase() == 'true';
  }

  static String? get testEmail {
    if (!isActive) return null;
    const fromDefine = String.fromEnvironment('DEV_TEST_EMAIL');
    if (fromDefine.isNotEmpty) return fromDefine;
    final v = dotenv.env['DEV_TEST_EMAIL']?.trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static String? get testPassword {
    if (!isActive) return null;
    const fromDefine = String.fromEnvironment('DEV_TEST_PASSWORD');
    if (fromDefine.isNotEmpty) return fromDefine;
    final v = dotenv.env['DEV_TEST_PASSWORD']?.trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static bool get hasAutoLogin => testEmail != null && testPassword != null;

  /// Passe l'animation du splash (~10 s). `flutter run` normal = false.
  static bool get skipSplash =>
      isActive && _envFlag('DEV_SKIP_SPLASH');

  /// Raccourci : splash court + connexion auto si identifiants dev présents.
  static bool get fastStart =>
      isActive && (_envFlag('DEV_FAST_START') || skipSplash);

  static String get loginButtonLabel =>
      dotenv.env['DEV_LOGIN_LABEL']?.trim().isNotEmpty == true
          ? dotenv.env['DEV_LOGIN_LABEL']!.trim()
          : 'Connexion test (dev)';
}
