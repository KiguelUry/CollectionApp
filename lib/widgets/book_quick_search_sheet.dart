import 'package:flutter/material.dart';

import '../models/book_subcategory.dart';
import 'book_search_dialog.dart' show showBookSearch;

/// @deprecated Utiliser [showBookSearch] ou [BookCatalogGridScreen].
Future<void> showBookQuickSearchSheet(
  BuildContext context, {
  required void Function(Map<String, String> book, BookSubcategory sub)
      onBookSelected,
  BookSubcategory initialSub = BookSubcategory.manga,
  String? initialQuery,
  VoidCallback? onManualEntry,
}) {
  return showBookSearch(
    context,
    onBookSelected: onBookSelected,
    initialSub: initialSub,
    initialQuery: initialQuery,
    onManualEntry: onManualEntry,
  );
}
