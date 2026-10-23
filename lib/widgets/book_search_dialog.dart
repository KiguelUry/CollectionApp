import 'package:flutter/material.dart';

import '../models/book_subcategory.dart';
import '../screens/book/book_catalog_grid_screen.dart';

/// Recherche livre — grille catalogue visuelle.
Future<void> showBookSearch(
  BuildContext context, {
  required void Function(Map<String, String> book, BookSubcategory subcategory)
      onBookSelected,
  void Function(
    String seriesName,
    BookSubcategory subcategory, {
    int? volumeCount,
    Map<int, String>? coversByVolume,
  })? onAddSeries,
  BookSubcategory initialSub = BookSubcategory.manga,
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
          Navigator.pop(ctx);
          onBookSelected(book, sub);
        },
        onAddSeries: onAddSeries == null
            ? null
            : (name, sub, {volumeCount, coversByVolume}) {
                Navigator.pop(ctx);
                onAddSeries(
                  name,
                  sub,
                  volumeCount: volumeCount,
                  coversByVolume: coversByVolume,
                );
              },
      ),
    ),
  );
}
