import 'package:flutter/material.dart';

/// Hauteur de contenu pour AlertDialog avec champ de recherche (clavier).
double adaptiveDialogContentHeight(
  BuildContext context, {
  double fraction = 0.72,
}) {
  final size = MediaQuery.sizeOf(context);
  final bottom = MediaQuery.viewInsetsOf(context).bottom;
  return (size.height * fraction - bottom).clamp(260.0, 520.0);
}
