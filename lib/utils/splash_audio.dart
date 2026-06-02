import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Son court au démarrage (fichier optionnel + bip système en secours).
class SplashAudio {
  static final AudioPlayer _player = AudioPlayer();
  static bool _played = false;

  static Future<void> playStartup() async {
    if (_played) return;
    _played = true;
    try {
      await _player.play(AssetSource('audio/splash_chime.mp3'));
      return;
    } catch (e) {
      if (kDebugMode) debugPrint('Splash audio asset: $e');
    }
    try {
      await SystemSound.play(SystemSoundType.click);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  static Future<void> dispose() => _player.dispose();
}
