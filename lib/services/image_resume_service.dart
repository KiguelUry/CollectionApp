import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../widgets/fail_safe_network_image.dart';

/// Au retour au premier plan : les bitmaps décodés ont souvent sauté, et les
/// URLs marquées « failed » restent blanches jusqu'à kill. On purge le ban
/// soft/hard et on notifie l'UI pour recharger.
class ImageResumeService with WidgetsBindingObserver, ChangeNotifier {
  ImageResumeService._();
  static final instance = ImageResumeService._();

  bool _bound = false;
  int _generation = 0;

  /// Incrémenté à chaque resume — les couvertures s'y abonnent.
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
    if (state != AppLifecycleState.resumed) return;
    clearFailedImageUrls();
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clearLiveImages();
      // Sur web, un clear total évite les textures CanvasKit fantômes.
      if (kIsWeb) cache.clear();
    } catch (_) {}
    _generation++;
    notifyListeners();
  }
}
