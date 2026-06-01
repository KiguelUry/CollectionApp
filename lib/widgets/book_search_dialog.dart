import 'package:flutter/material.dart';

import '../models/book_subcategory.dart';
import 'book_quick_search_sheet.dart';

/// Recherche livre (bottom sheet).
Future<void> showBookSearch(
  BuildContext context, {
  required void Function(Map<String, String> book, BookSubcategory subcategory)
      onBookSelected,
  BookSubcategory initialSub = BookSubcategory.manga,
  VoidCallback? onManualEntry,
}) {
  return showBookQuickSearchSheet(
    context,
    onBookSelected: onBookSelected,
    initialSub: initialSub,
    onManualEntry: onManualEntry,
  );
}
