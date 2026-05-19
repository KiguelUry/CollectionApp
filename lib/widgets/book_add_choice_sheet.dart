import 'package:flutter/material.dart';

enum BookAddChoice {
  series,
  book,
}

Future<BookAddChoice?> showBookAddChoiceSheet(BuildContext context) {
  return showModalBottomSheet<BookAddChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Que veux-tu ajouter ?',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                child: const Icon(Icons.auto_stories),
              ),
              title: const Text('Une série'),
              subtitle: const Text(
                'Rechercher « Thorgal », « Naruto »… puis gérer les tomes',
              ),
              onTap: () => Navigator.pop(ctx, BookAddChoice.series),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(ctx).colorScheme.secondaryContainer,
                child: const Icon(Icons.menu_book),
              ),
              title: const Text('Un livre / tome'),
              subtitle: const Text(
                'ISBN, recherche titre — la série est créée si détectée',
              ),
              onTap: () => Navigator.pop(ctx, BookAddChoice.book),
            ),
          ],
        ),
      ),
    ),
  );
}
