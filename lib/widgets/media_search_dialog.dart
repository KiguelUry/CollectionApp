import 'package:flutter/material.dart';

import '../models/category_metadata.dart';
import 'media_quick_search_sheet.dart';

Future<Map<String, String>?> showMediaSearch(
  BuildContext context, {
  required MediaFormat format,
  VoidCallback? onManualEntry,
}) {
  return showMediaQuickSearchSheet(
    context,
    initialFormat: format,
    onManualEntry: onManualEntry,
  );
}
