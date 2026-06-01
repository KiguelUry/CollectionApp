import 'package:flutter/material.dart';

import '../models/card_subcategory.dart';
import 'card_quick_search_sheet.dart';

/// Recherche carte (bottom sheet).
Future<Map<String, String>?> showCardSearch(
  BuildContext context, {
  required CardSubcategory subcategory,
  VoidCallback? onManualEntry,
}) {
  return showCardQuickSearchSheet(
    context,
    initialSub: subcategory,
    onManualEntry: onManualEntry,
  );
}
