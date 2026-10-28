import 'package:flutter/material.dart';

import '../models/book_subcategory.dart';
import '../screens/book/book_catalog_grid_screen.dart';

/// Recherche livre — grille catalogue visuelle.
Future<void> showBookSearch(
  BuildContext context, {
  required void Function(Map<String, String> book, BookSubcategory subcategory)
      onBookSelected,
  Future<bool> Function(
    String seriesName,
    BookSubcategory subcategory, {
    int? volumeCount,
    Map<int, String>? coversByVolume,
    Map<int, String>? publishedDatesByVolume,
    String? author,
  })? onAddSeries,
  BookSubcategory? initialSub,
  String? initialQuery,
  VoidCallback? onManualEntry,
}) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (ctx) => BookCatalogGridScreen(
        initialSub: initialSub,
        initialQuery: initialQuery,
        onBookSelected: (book, sub) {
          // Tomes individuels : ferme la recherche (comportement historique).
          Navigator.pop(ctx);
          onBookSelected(book, sub);
        },
        // Séries : reste sur la page de recherche.
        onAddSeries: onAddSeries,
      ),
    ),
  );
}
