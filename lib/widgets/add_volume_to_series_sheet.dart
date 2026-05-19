import 'package:flutter/material.dart';

enum AddVolumeToSeriesChoice { search, isbn, manual }

Future<AddVolumeToSeriesChoice?> showAddVolumeToSeriesSheet(BuildContext context) {
  return showModalBottomSheet<AddVolumeToSeriesChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ajouter un tome',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Rechercher (Open Library)'),
              subtitle: const Text('Ex. Walking Dead, Thorgal…'),
              onTap: () => Navigator.pop(ctx, AddVolumeToSeriesChoice.search),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scanner l\'ISBN'),
              onTap: () => Navigator.pop(ctx, AddVolumeToSeriesChoice.isbn),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Saisie manuelle'),
              onTap: () => Navigator.pop(ctx, AddVolumeToSeriesChoice.manual),
            ),
          ],
        ),
      ),
    ),
  );
}
