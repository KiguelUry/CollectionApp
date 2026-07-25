import 'package:flutter/material.dart';

import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../screens/item_detail_screen.dart';
import '../services/boardgame_expansion_service.dart';
import '../utils/boardgame_display.dart';
import '../utils/boardgame_expansions.dart';
import '../utils/holder_label_utils.dart';
import '../utils/item_group_count.dart';
import 'boardgame_tile_inventory_sheets.dart';
import 'boardgame_tile_sheets.dart';
import 'wishlist/wishlist_tile_meta_icons.dart';

/// Cinq icônes interactives (quantité, groupe, extensions, lieu, note BGG).
class BoardgameTileMetaIcons extends StatelessWidget {
  final CollectionItem item;
  final int ownedQuantity;
  final bool showGroupBadge;
  final List<CollectionGroup> groups;
  final Map<String, int> groupActivityCounts;
  final bool readOnly;
  final String? contextGroupId;
  final Future<void> Function(CollectionItem base)? onExpansionBaseFocus;

  const BoardgameTileMetaIcons({
    super.key,
    required this.item,
    required this.ownedQuantity,
    this.showGroupBadge = true,
    this.groups = const [],
    this.groupActivityCounts = const {},
    this.readOnly = false,
    this.contextGroupId,
    this.onExpansionBaseFocus,
  });

  int get _groupCount =>
      groupMembershipCount(item, contextGroupId: contextGroupId);

  String? get _locationChipLabel {
    final label = item.locationLabel?.trim();
    if (label != null && label.isNotEmpty) {
      final plain = holderLabelStorageValue(label).trim();
      if (plain.isNotEmpty) return plain;
    }
    final custom = item.metadata?['holder_label']?.toString().trim();
    if (custom != null && custom.isNotEmpty) {
      return holderLabelStorageValue(custom);
    }
    return null;
  }

  String? get _bggRatingLabel =>
      formatBggRatingChipLabel(item.metadata?['bgg_avg_rating']);

  Future<void> _showQuantitySheet(BuildContext context) {
    return showBoardgameTileQuantitySheet(
      context,
      item: item,
      ownedQuantity: ownedQuantity,
      readOnly: readOnly,
    );
  }

  Future<void> _showGroupSheet(BuildContext context) {
    return showBoardgameTileGroupSheet(
      context,
      item: item,
      groups: groups,
      groupActivityCounts: groupActivityCounts,
      readOnly: readOnly,
    );
  }

  Future<void> _showExpansionSheet(BuildContext context) {
    return showBoardgameTileExpansionSheet(
      context,
      item: item,
      readOnly: readOnly,
    );
  }

  Future<void> _openExpansionContext(BuildContext context) async {
    if (!(item.isExpansion ||
        (item.parentGameId != null && item.parentGameId!.isNotEmpty) ||
        item.metadata?['bgg_is_expansion'] == true)) {
      return _showExpansionSheet(context);
    }
    final service = BoardgameExpansionService();
    CollectionItem? base;
    final parentId = item.parentGameId;
    if (parentId != null && parentId.isNotEmpty) {
      base = await service.findBaseByItemId(parentId);
    }
    base ??= await service.findBaseByBggId(
      item.metadata?['base_game_bgg_id']?.toString() ??
          item.metadata?['expansion_of_bgg_id']?.toString() ??
          '',
    );
    if (!context.mounted || base == null) return;
    if (onExpansionBaseFocus != null) {
      await onExpansionBaseFocus!(base);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailScreen(item: base!)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Extension liée à « ${base.title} »')),
    );
  }

  Future<void> _showRatingSheet(BuildContext context) {
    return showBoardgameTileRatingSheet(
      context,
      item: item,
      readOnly: readOnly,
    );
  }

  Future<void> _showLocationSheet(BuildContext context) {
    return showBoardgameTileLocationSheet(
      context,
      item: item,
      groups: groups,
      readOnly: readOnly,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (item.isWishlist) {
      return WishlistTileMetaIcons(item: item, readOnly: readOnly);
    }

    final groupCount = !item.isSold ? _groupCount : 0;
    final expansionCount = ownedExpansionCount(item);
    final location = _locationChipLabel;
    final rating = _bggRatingLabel;
    final isExpansionTile = item.isExpansion ||
        (item.parentGameId != null && item.parentGameId!.isNotEmpty) ||
        item.metadata?['bgg_is_expansion'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _showQuantitySheet(context),
                behavior: HitTestBehavior.opaque,
                child: _metaChip(
                  icon: Icons.layers_outlined,
                  suffix: '$ownedQuantity',
                  color: Colors.lightBlue.shade600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => _showGroupSheet(context),
                behavior: HitTestBehavior.opaque,
                child: _metaChip(
                  icon: groupCount > 1 ? Icons.groups : Icons.group_outlined,
                  suffix: '$groupCount',
                  color: Colors.teal.shade500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => _openExpansionContext(context),
                behavior: HitTestBehavior.opaque,
                child: _metaChip(
                  icon: isExpansionTile
                      ? Icons.subdirectory_arrow_right
                      : Icons.extension_outlined,
                  suffix: isExpansionTile ? 'Ext' : '$expansionCount',
                  color: isExpansionTile
                      ? Colors.deepPurple.shade500
                      : Colors.green.shade600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: () => _showLocationSheet(context),
                behavior: HitTestBehavior.opaque,
                child: _metaChip(
                  icon: Icons.place_outlined,
                  suffix: location ?? '—',
                  color: Colors.deepOrange.shade400,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => _showRatingSheet(context),
                behavior: HitTestBehavior.opaque,
                child: _metaChip(
                  icon: Icons.star_rounded,
                  suffix: rating ?? '—',
                  color: Colors.amber.shade700,
                  shrinkSuffix: true,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metaChip({
    required IconData icon,
    String? suffix,
    required Color color,
    bool shrinkSuffix = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          if (suffix != null) ...[
            const SizedBox(width: 2),
            Expanded(
              child: shrinkSuffix
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        suffix,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: color,
                          height: 1,
                        ),
                      ),
                    )
                  : Text(
                      suffix,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                        height: 1,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
