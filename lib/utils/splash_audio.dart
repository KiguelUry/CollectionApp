import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Son court au démarrage (arpège doux ~1 s, bip système en secours).
class SplashAudio {
  static final AudioPlayer _player = AudioPlayer();
  static bool _played = false;
  static Timer? _fadeTimer;

  static const _assetCandidates = [
    'audio/splash_guitar_soft.wav',
    'audio/splash_welcome.wav',
    'audio/splash_chime.wav',
    'audio/splash_chime.mp3',
  ];

  static Future<void> playStartup() async {
    if (_played) return;
    _played = true;
    for (final asset in _assetCandidates) {
      try {
        await _player.setVolume(1);
        await _player.play(AssetSource(asset));
        _scheduleFadeOut(const Duration(milliseconds: 2800));
        return;
      } catch (e) {
        if (kDebugMode) debugPrint('Splash audio ($asset): $e');
      }
    }
    try {
      await SystemSound.play(SystemSoundType.click);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  static void _scheduleFadeOut(Duration delay) {
    _fadeTimer?.cancel();
    _fadeTimer = Timer(delay, () async {
      for (var step = 10; step >= 0; step--) {
        try {
          await _player.setVolume(step / 10);
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
      try {
        await _player.stop();
      } catch (_) {}
    });
  }

  static Future<void> dispose() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    await _player.dispose();
  }
}
