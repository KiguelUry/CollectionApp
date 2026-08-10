import 'package:flutter/material.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../utils/boardgame_display.dart';
import '../utils/app_page_route.dart';
import 'bgg_network_image.dart';
import 'boardgame_tile_meta_icons.dart';
import 'item_title_text.dart';
import 'wishlist/wishlist_tile_meta_icons.dart';

/// Ligne liste (vue dense type Libib).
class CollectionItemListTile extends StatelessWidget {
  final CollectionItem item;
  final CollectionCategory category;
  final int totalQuantity;
  final int? ownedQuantity;
  final List<CollectionGroup>? boardgameQuickEditGroups;
  final Map<String, int> groupActivityCounts;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final Future<void> Function(CollectionItem base)? onExpansionBaseFocus;

  const CollectionItemListTile({
    super.key,
    required this.item,
    required this.category,
    this.totalQuantity = 1,
    this.ownedQuantity,
    this.boardgameQuickEditGroups,
    this.groupActivityCounts = const {},
    this.onTap,
    this.onDelete,
    this.onExpansionBaseFocus,
  });

  bool get _isBoardgame => category == CollectionCategory.boardgame;

  int get _ownedQty =>
      ownedQuantity ?? (item.isWishlist ? 0 : totalQuantity);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: item.imageUrl != null
                      ? Hero(
                          tag: collectionCoverHeroTag(item.id),
                          child: BggNetworkImage(
                            key: ValueKey('${item.id}:${item.imageUrl}'),
                            url: item.imageUrl!,
                            width: 56,
                            height: 56,
                            bookCover: category == CollectionCategory.book,
                            boxedCover:
                                category == CollectionCategory.boardgame,
                            compact: true,
                          ),
                        )
                      : ColoredBox(
                          color: category.color.withValues(alpha: 0.15),
                          child: Icon(category.icon, color: category.color),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ItemTitleText(
                      title: item.title,
                      maxLines: 3,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_subtitleLine != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _subtitleLine!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    if (_isBoardgame && boardgameQuickEditGroups != null) ...[
                      const SizedBox(height: 8),
                      item.isWishlist
                          ? WishlistTileMetaIcons(item: item)
                          : BoardgameTileMetaIcons(
                              item: item,
                              ownedQuantity: _ownedQty,
                              groups: boardgameQuickEditGroups!,
                              groupActivityCounts: groupActivityCounts,
                              onExpansionBaseFocus: onExpansionBaseFocus,
                            ),
                    ] else ...[
                      if (_whereLine != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _whereLine!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                      if (item.tags.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: item.tags
                              .map(
                                (t) => Chip(
                                  label: Text(
                                    t.label,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor:
                                      t.color.withValues(alpha: 0.2),
                                  side: BorderSide.none,
                                  padding: EdgeInsets.zero,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: Colors.grey.shade600,
                  ),
                  tooltip: 'Supprimer',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
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
