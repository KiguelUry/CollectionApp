import 'package:flutter/material.dart';

/// Navigation globale — écran « Collections » = accueil de l'app.
class AppNavigation {
  static const collectionsRoute = '/categories';

  static void openCollections(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      collectionsRoute,
      (route) => false,
    );
  }

  static bool isOnCollectionsHome(BuildContext context) {
    final name = ModalRoute.of(context)?.settings.name;
    return name == collectionsRoute;
  }
}
