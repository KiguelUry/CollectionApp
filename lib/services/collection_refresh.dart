import 'package:flutter/foundation.dart';

/// Notifie les écrans collection qu'un ajout/suppression a eu lieu (stream parfois lent).
class CollectionRefresh extends ChangeNotifier {
  CollectionRefresh._();
  static final instance = CollectionRefresh._();

  void bump() => notifyListeners();
}
