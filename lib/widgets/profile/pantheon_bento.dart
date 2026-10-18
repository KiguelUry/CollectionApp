import 'package:flutter/material.dart';

import '../../models/collection_item.dart';
import '../collection_cover_image.dart';

/// Vitrine Top 10 : cartes format boîte (couverture pleine), podium puis #4–#10.
class PantheonBento extends StatelessWidget {
  final List<CollectionItem> ranked;
  final bool editable;
  final int slotCount;
  final VoidCallback? onAutoFill;
  final VoidCallback? onExtend;
  final ValueChanged<int>? onEditSlot;
  final ValueChanged<int>? onRemove;
  final void Function(int oldIndex, int newIndex)? onReorder;

  const PantheonBento({
    super.key,
    required this.ranked,
    this.editable = false,
    this.slotCount = 10,
    this.onAutoFill,
    this.onExtend,
    this.onEditSlot,
    this.onRemove,
    this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    if (!editable && ranked.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Panthéon · Top $slotCount',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (editable && onAutoFill != null)
              TextButton(
                onPressed: onAutoFill,
                child: const Text('Remplir automatiquement mon Top'),
              ),
            if (editable && onExtend != null && slotCount < 20)
              TextButton(
                onPressed: onExtend,
                child: const Text('Étendre jusqu\'à 20'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            _card(context, 1, width: 132, height: 176),
            _card(context, 0, width: 150, height: 200),
            _card(context, 2, width: 132, height: 176),
          ],
        ),
        const SizedBox(height: 12),
        if (editable && onReorder != null)
          SizedBox(
            height: 176,
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: true,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                onReorder!(oldIndex + 3, newIndex + 3);
              },
              children: [
                for (var i = 3; i < slotCount; i++)
                  Padding(
                    key: ValueKey(
                      'pantheon-$i-${ranked.length > i ? ranked[i].id : 'empty'}',
                    ),
                    padding: const EdgeInsets.only(right: 8),
                    child: _card(context, i, width: 112, height: 168),
                  ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 3; i < (editable ? slotCount : ranked.length); i++)
                _card(context, i, width: 112, height: 168),
            ],
          ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    int index, {
    required double width,
    required double height,
  }) {
    if (!editable && index >= ranked.length) return const SizedBox.shrink();
    final item = index < ranked.length ? ranked[index] : null;
    final rank = index + 1;
    final accent = switch (index) {
      0 => Colors.amber.shade700,
      1 => Colors.blueGrey.shade500,
      2 => Colors.brown.shade400,
      _ => Theme.of(context).colorScheme.outline,
    };
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: editable && onEditSlot != null ? () => onEditSlot!(index) : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item?.imageUrl != null)
                CollectionCoverImage(
                  url: item!.imageUrl!,
                  boxedCover: true,
                  compact: true,
                  fit: BoxFit.cover,
                )
              else
                Icon(Icons.casino_outlined, color: accent, size: 36),
              if (editable && item != null && onRemove != null)
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => onRemove!(index),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ),
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.62),
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                  child: Text(
                    item?.title ?? 'Choisir',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
