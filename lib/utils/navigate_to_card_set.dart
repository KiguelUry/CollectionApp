import 'package:flutter/material.dart';

import '../models/collection_item.dart';
import '../models/tcg_set_info.dart';
import '../screens/tcg/tcg_set_cards_screen.dart';

/// Ouvre le catalogue sur la série de la carte (si `set_id` connu).
bool openCardSetCatalog(BuildContext context, CollectionItem item) {
  final sub = item.cardSubcategory;
  if (sub == null || !sub.hasSetBrowser) return false;

  final meta = item.metadata ?? {};
  final setId = meta['set_id']?.toString().trim() ?? '';
  if (setId.isEmpty) return false;

  final setName = meta['set_name']?.toString().trim();
  final set = TcgSetInfo(
    id: setId,
    name: setName?.isNotEmpty == true ? setName! : setId,
    code: setId,
    seriesName: meta['block_name']?.toString() ??
        meta['series_name']?.toString() ??
        '',
  );

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => TcgSetCardsScreen(subcategory: sub, set: set),
    ),
  );
  return true;
}
