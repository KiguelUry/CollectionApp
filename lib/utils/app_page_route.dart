import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Tag Hero stable pour les jaquettes grille ↔ détail.
String collectionCoverHeroTag(String itemId) => 'collection-cover-$itemId';

/// Navigation avec transition Cupertino (cohérente avec [AppTheme]).
Route<T> appPageRoute<T extends Object?>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  return CupertinoPageRoute<T>(
    builder: builder,
    settings: settings,
    fullscreenDialog: fullscreenDialog,
  );
}
