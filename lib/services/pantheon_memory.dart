import 'package:flutter/foundation.dart';

/// Dernier Panthéon connu, pour mettre à jour la fiche et le profil ensemble.
class PantheonMemory extends ChangeNotifier {
  PantheonMemory._();
  static final PantheonMemory instance = PantheonMemory._();

  final Map<String, List<String>> _ids = {};

  List<String>? idsFor(String userId) {
    final list = _ids[userId];
    if (list == null) return null;
    return List<String>.from(list);
  }

  void publish(String userId, List<String> ids) {
    _ids[userId] = List<String>.from(ids);
    notifyListeners();
  }
}
