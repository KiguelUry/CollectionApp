import 'package:flutter/material.dart';

import '../coordinators/book_item_add_coordinator.dart';
import '../coordinators/series_add_coordinator.dart';
import '../models/book_subcategory.dart';
import '../widgets/book_add_choice_sheet.dart';

/// Menu d'ajout : série (recherche Thorgal…) ou livre/tome.
Future<void> openBookAddFlow(
  BuildContext context, {
  required BookSubcategory subcategory,
}) async {
  final choice = await showBookAddChoiceSheet(context);
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case BookAddChoice.series:
      await SeriesAddCoordinator(context).openSeriesSearch(subcategory);
    case BookAddChoice.book:
      final mode = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Rechercher un titre'),
                onTap: () => Navigator.pop(ctx, 'search'),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scanner ISBN'),
                onTap: () => Navigator.pop(ctx, 'isbn'),
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Saisie manuelle'),
                onTap: () => Navigator.pop(ctx, 'manual'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted || mode == null) return;
      final add = BookItemAddCoordinator(context);
      switch (mode) {
        case 'search':
          await add.openSearch(subcategory: subcategory);
        case 'isbn':
          await add.scanIsbn();
        case 'manual':
          await add.openManual(subcategory: subcategory);
      }
  }
}
