import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/collection_category.dart';

/// Grilles plus denses sur web PC ; mobile natif (Android/iOS) inchangé.
abstract final class CollectionGridLayout {
  static bool isWebDesktop(BuildContext context) {
    if (!kIsWeb) return false;
    return MediaQuery.sizeOf(context).width >= 720;
  }

  /// `mobile` = colonnes sur app native et web étroit.
  static int columns(BuildContext context, {required int mobile}) {
    if (!kIsWeb) return mobile;
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) return mobile;
    if (w < 900) return mobile + 3;
    if (w < 1200) return mobile + 4;
    if (w < 1600) return mobile + 5;
    return mobile + 6;
  }

  static int crossAxisCount(BuildContext context, {int mobile = 3}) =>
      columns(context, mobile: mobile);

  static int hubColumns(BuildContext context) => columns(context, mobile: 2);

  static int tcgCardColumns(BuildContext context) =>
      columns(context, mobile: 3);

  static int tcgSetColumns(BuildContext context) => columns(context, mobile: 2);

  static double? maxContentWidth(BuildContext context) {
    if (!isWebDesktop(context)) return null;
    final w = MediaQuery.sizeOf(context).width;
    return w.clamp(1280.0, 1680.0);
  }

  static const double gridCrossSpacing = 12;

  /// Espacement vertical entre tuiles (même colonne).
  static const double gridMainSpacing = 7;

  /// Hauteur max du pied de tuile (titre + stats + 2 rangées d'icônes).
  static const double boardgameMaxFooterHeight = 108;

  static double _boardgameCellWidth(
    BuildContext context, {
    required int mobileColumns,
    double gridPadding = 24,
    double crossSpacing = 12,
  }) {
    final cols = columns(context, mobile: mobileColumns);
    final w = MediaQuery.sizeOf(context).width;
    return (w - gridPadding - crossSpacing * (cols - 1)) / cols;
  }

  static double aspectRatio(
    CollectionCategory category,
    BuildContext context, {
    int mobileColumns = 3,
    double gridPadding = 24,
    double crossSpacing = 12,
  }) {
    if (category == CollectionCategory.boardgame) {
      final cellW = _boardgameCellWidth(
        context,
        mobileColumns: mobileColumns,
        gridPadding: gridPadding,
        crossSpacing: crossSpacing,
      );
      return cellW / (cellW + boardgameMaxFooterHeight);
    }
    final base = switch (category) {
      CollectionCategory.card => 0.5,
      _ => 0.85,
    };
    return base;
  }

  static SliverGridDelegateWithFixedCrossAxisCount gridDelegate(
    BuildContext context, {
    required int mobileColumns,
    required double childAspectRatio,
    double spacing = 12,
  }) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns(context, mobile: mobileColumns),
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
    );
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
