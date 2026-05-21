import 'package:flutter/material.dart';

import '../../models/collection_item.dart';
import '../collection_cover_image.dart';

/// Choisir un objet de la collection pour un emplacement trophée.
Future<CollectionItem?> showTrophyPickerSheet(
  BuildContext context, {
  required List<CollectionItem> candidates,
  required Set<String> alreadyPickedIds,
}) {
  return showModalBottomSheet<CollectionItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final available = candidates
          .where((c) => !alreadyPickedIds.contains(c.id))
          .toList();

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Choisir un trophée',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              if (available.isEmpty)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucun autre objet disponible.\nAjoute des pièces à ta collection.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: available.length,
                    itemBuilder: (context, index) {
                      final item = available[index];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CollectionCoverImage(
                            url: item.imageUrl ?? '',
                            width: 48,
                            height: 48,
                            bookCover: item.category.name == 'book',
                          ),
                        ),
                        title: Text(item.title, maxLines: 2),
                        subtitle: Text(item.category.label),
                        onTap: () => Navigator.pop(ctx, item),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}
