import 'package:flutter/material.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/boardgame_display.dart';
import 'bgg_network_image.dart';

/// Ligne liste (vue dense type Libib).
class CollectionItemListTile extends StatelessWidget {
  final CollectionItem item;
  final CollectionCategory category;
  final int totalQuantity;
  final VoidCallback? onTap;

  const CollectionItemListTile({
    super.key,
    required this.item,
    required this.category,
    this.totalQuantity = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 52,
            height: 52,
            child: item.imageUrl != null
                ? BggNetworkImage(
                    url: item.imageUrl!,
                    bookCover: category == CollectionCategory.book,
                  )
                : ColoredBox(
                    color: category.color.withValues(alpha: 0.15),
                    child: Icon(category.icon, color: category.color),
                  ),
          ),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_subtitleLine != null)
              Text(
                _subtitleLine ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            if (_whereLine != null)
              Text(
                _whereLine!,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            if (item.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: item.tags
                      .map(
                        (t) => Chip(
                          label: Text(t.label, style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: t.color.withValues(alpha: 0.2),
                          side: BorderSide.none,
                          padding: EdgeInsets.zero,
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.isGroupOwned)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.groups, size: 18, color: Colors.deepPurple.shade400),
              ),
            if (totalQuantity > 1)
              Text(
                '×$totalQuantity',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
          ],
        ),
        isThreeLine: item.tags.isNotEmpty || _whereLine != null,
      ),
    );
  }

  String? get _subtitleLine {
    if (category == CollectionCategory.boardgame) {
      final parts = <String>[];
      final players = formatPlayerCount(item.minPlayers, item.maxPlayers);
      if (players != null) parts.add(players);
      final time = formatPlayingTime(item.playingTime);
      if (time != null) parts.add(time);
      return parts.isEmpty ? null : parts.join(' · ');
    }
    return item.listSubtitle;
  }

  String? get _whereLine {
    if (item.locationLabel == null || item.locationLabel!.trim().isEmpty) {
      return null;
    }
    return item.locationLabel;
  }
}
