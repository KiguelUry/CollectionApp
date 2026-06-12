import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/collection_category.dart';

/// Grille collection : plus compacte sur web PC, inchangée sur mobile natif.
abstract final class CollectionGridLayout {
  /// Web sur écran large (PC) — pas l'app Android/iOS.
  static bool isWebDesktop(BuildContext context) {
    if (!kIsWeb) return false;
    return MediaQuery.sizeOf(context).width >= 720;
  }

  static int crossAxisCount(BuildContext context, {int mobile = 3}) {
    if (!kIsWeb) return mobile;
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) return mobile;
    if (w < 900) return mobile + 2;
    if (w < 1200) return mobile + 3;
    return mobile + 4;
  }

  static double? maxContentWidth(BuildContext context) {
    if (!isWebDesktop(context)) return null;
    return 1280;
  }

  static double aspectRatio(CollectionCategory category, BuildContext context) {
    final base = switch (category) {
      CollectionCategory.boardgame => 0.72,
      CollectionCategory.card => 0.5,
      _ => 0.85,
    };
    if (isWebDesktop(context) && category == CollectionCategory.boardgame) {
      return 0.82;
    }
    return base;
  }

  static Widget constrainOnWebDesktop({
    required BuildContext context,
    required Widget child,
  }) {
    final maxW = maxContentWidth(context);
    if (maxW == null) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: child,
      ),
    );
  }
}
