import 'package:flutter/material.dart';

import '../utils/book_title_parser.dart';

/// true = lier à la série, false = ajouter sans série, null = annuler.
Future<bool?> showSeriesLinkConfirmDialog(
  BuildContext context, {
  required ParsedBookTitle parsed,
  int? estimatedVolumeCount,
}) {
  final vol = parsed.volumeNumber;
  final volLabel = vol != null
      ? (vol == vol.roundToDouble() ? vol.toInt().toString() : vol.toString())
      : null;

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Série détectée'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '« ${parsed.seriesName} »',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          if (volLabel != null) ...[
            const SizedBox(height: 8),
            Text('Tome $volLabel'),
          ],
          if (estimatedVolumeCount != null && estimatedVolumeCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Environ $estimatedVolumeCount tomes repérés (Open Library)',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Créer ou ouvrir cette série dans ta collection manga/BD '
            'et y ranger ce livre ?',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Sans série'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Oui, lier'),
        ),
      ],
    ),
  );
}
