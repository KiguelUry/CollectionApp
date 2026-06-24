import 'package:flutter/material.dart';

import '../../models/collection_category.dart';
import '../../services/quick_log_service.dart';
import '../collection_cover_image.dart';

String _formatLogDate(DateTime dt) {
  const months = [
    'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
    'juil', 'aoû', 'sep', 'oct', 'nov', 'déc',
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${months[dt.month - 1]} ${dt.year} · $h:$m';
}

/// Timeline chronologique du journal Quick Log.
class QuickLogTimeline extends StatelessWidget {
  final List<QuickLogEntry> entries;
  final VoidCallback? onAdd;
  final void Function(QuickLogEntry entry)? onDelete;

  const QuickLogTimeline({
    super.key,
    required this.entries,
    this.onAdd,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Journal d\'activité',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (onAdd != null)
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Quick Log'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            'Note une session de lecture, une partie…',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          )
        else
          ...entries.map((e) {
            final cat = e.itemCategory != null
                ? CollectionCategory.fromDbValue(e.itemCategory!)
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: cat?.color ?? theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (e.itemImageUrl != null &&
                                e.itemImageUrl!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CollectionCoverImage(
                                    url: e.itemImageUrl!,
                                    width: 44,
                                    height: 44,
                                    bookCover:
                                        cat == CollectionCategory.book,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.note,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatLogDate(e.loggedAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (onDelete != null)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => onDelete!(e),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
