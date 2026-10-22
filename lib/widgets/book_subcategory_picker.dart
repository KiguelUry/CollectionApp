import 'package:flutter/material.dart';

import '../models/book_subcategory.dart';

/// Choix rapide manga / BD / roman après scan ISBN ou saisie.
Future<BookSubcategory?> showBookSubcategoryPicker(
  BuildContext context, {
  BookSubcategory? suggested,
}) {
  return showDialog<BookSubcategory>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Type de livre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in BookSubcategory.values)
            ListTile(
              title: Text(s.label),
              leading: Icon(
                s.icon,
              ),
              selected: s == suggested,
              onTap: () => Navigator.pop(ctx, s),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
}
