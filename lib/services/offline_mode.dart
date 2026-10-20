import 'package:flutter/foundation.dart';

/// État hors-ligne de la session : consultation locale sans écran bloquant.
class OfflineMode extends ChangeNotifier {
  OfflineMode._();
  static final OfflineMode instance = OfflineMode._();

  bool _active = false;

  bool get active => _active;

  void setOffline([bool value = true]) {
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }

  void setOnline() => setOffline(false);

  /// Marque hors-ligne si [error] ressemble à une panne réseau.
  bool markIfNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    final offline = text.contains('socket') ||
        text.contains('network') ||
        text.contains('failed host lookup') ||
        text.contains('connection') ||
        text.contains('offline') ||
        text.contains('clientexception') ||
        text.contains('xmlhttprequest');
    if (offline) setOffline(true);
    return offline;
  }
}
