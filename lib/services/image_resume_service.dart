import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../widgets/fail_safe_network_image.dart';

/// Au retour au premier plan : les URLs marquées « failed » restent blanches.
/// On purge le ban soft/hard et on notifie l'UI — **sans** vider tout le
/// ImageCache à chaque alt-tab (sinon clignotement permanent sur web).
class ImageResumeService with WidgetsBindingObserver, ChangeNotifier {
  ImageResumeService._();
  static final instance = ImageResumeService._();

  bool _bound = false;
  int _generation = 0;
  DateTime? _lastPurge;
  DateTime? _lastBackgroundAt;

  /// Incrémenté quand on force un rechargement des couvertures.
  int get generation => _generation;

  void start() {
    if (_bound) return;
    _bound = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (_bound) {
      WidgetsBinding.instance.removeObserver(this);
      _bound = false;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _lastBackgroundAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    final now = DateTime.now();
    // Alt-tab / focus web : debounce pour éviter le flash permanent.
    if (_lastPurge != null &&
        now.difference(_lastPurge!) < const Duration(milliseconds: 2500)) {
      _lastBackgroundAt = null;
      return;
    }
    _lastPurge = now;

    final away = _lastBackgroundAt == null
        ? Duration.zero
        : now.difference(_lastBackgroundAt!);
    _lastBackgroundAt = null;

    clearFailedImageUrls();

    try {
      final cache = PaintingBinding.instance.imageCache;
      // Pause courte (alt-tab) : pas de clear cache → pas de clignotement.
      if (away > const Duration(seconds: 45)) {
        cache.clearLiveImages();
      }
      if (kIsWeb && away > const Duration(minutes: 3)) {
        cache.clear();
      }
    } catch (_) {}

    // Rebuild couvertures seulement si on a vraiment quitté un moment
    // ou s'il y avait des URLs en échec (déjà purgées).
    if (away > const Duration(seconds: 8)) {
      _generation++;
      notifyListeners();
    }
  }
}
