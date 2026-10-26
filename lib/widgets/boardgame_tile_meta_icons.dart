import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../screens/item_detail_screen.dart';
import '../services/boardgame_expansion_service.dart';
import '../utils/boardgame_display.dart';
import '../utils/boardgame_expansions.dart';
import '../utils/item_copy_units.dart';
import '../utils/item_group_count.dart';
import '../utils/tile_rating_display.dart';
import '../utils/wishlist_market_metadata.dart';
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

  String? _meUserIdSafe() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? get _locationChipLabel {
    if (item.isOnLoan) return item.loaneeDisplayName;
    if (itemUsesCopyUnits(item)) {
      final summary = quickWhereaboutsSummaryLabel(
        item,
        meUserId: _meUserIdSafe(),
      );
      if (summary.startsWith('Chez ')) {
        return summary.substring(5).trim();
      }
      if (summary.startsWith('À ')) {
        return summary.substring(2).trim();
      }
      return summary.trim().isEmpty ? null : summary;
    }
    final label = item.locationLabel?.trim();
    if (label != null && label.isNotEmpty) {
      if (label.toLowerCase().startsWith('chez ')) {
        return label.substring(5).trim();
      }
      return label;
    }
    final custom = item.metadata?['holder_label']?.toString().trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return null;
  }

  TileRatingChip get _ratingChip => resolveTileRating(
        personalOnFive: personalRatingOnFive(
          item.rating,
          metadata: item.metadata,
        ),
        communityOnFive: bggRatingOnFive(item.metadata?['bgg_avg_rating']),
      );

  String? get _bggRatingLabel {
    final chip = _ratingChip;
    if (chip.label == TileRatingChip.empty.label) return null;
    return chip.label.replaceFirst('★ ', '');
  }

  Future<void> _showQuantitySheet(BuildContext context) {
    return showBoardgameTileQuantitySheet(
      context,
      item: item,
      ownedQuantity: ownedQuantity,
      readOnly: readOnly,
    );
  }

  /// Moyenne marché en cache (`~`), sinon prix payé sans tilde.
  String get _valueChipLabel {
    final avg = marketPriceAvgFromMetadata(item.metadata);
    if (avg != null && avg > 0) {
      return '~${formatEuroChip(avg, compact: false)}';
    }
    final market = marketSecondhandPriceFromMetadata(item.metadata);
    if (market != null) return '~${formatEuroChip(market, compact: false)}';
    final paid = copyPurchasePricesFromRow(
      quantity: item.quantity,
      purchasePrice: item.purchasePrice,
      metadata: item.metadata,
    ).whereType<double>().fold<double>(0, (a, b) => a + b);
    return paid > 0 ? formatEuroChip(paid, compact: false) : '—';
  }

  Future<void> _showValueSheet(BuildContext context) {
    return showBoardgameTileValueSheet(
      context,
      item: item,
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

    final narrow = MediaQuery.sizeOf(context).width < 600;

    Widget quantityChip() => GestureDetector(
          onTap: () => _showQuantitySheet(context),
          behavior: HitTestBehavior.opaque,
          child: _metaChip(
            icon: Icons.layers_outlined,
            suffix: '$ownedQuantity',
            color: Colors.lightBlue.shade600,
          ),
        );

    Widget valueChip() => GestureDetector(
          onTap: () => _showValueSheet(context),
          behavior: HitTestBehavior.opaque,
          child: _metaChip(
            suffix: _valueChipLabel,
            color: Colors.teal.shade500,
            textOnly: true,
          ),
        );

    Widget expansionChip() => GestureDetector(
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
        );

    Widget locationChip() => GestureDetector(
          onTap: () => _showLocationSheet(context),
          behavior: HitTestBehavior.opaque,
          child: _metaChip(
            key: item.isOnLoan ? const ValueKey('loan_location_chip') : null,
            icon: item.isOnLoan
                ? Icons.handshake_outlined
                : Icons.place_outlined,
            suffix: location ?? '—',
            color: item.isOnLoan
                ? Colors.blue.shade600
                : Colors.deepOrange.shade400,
            groupCount: groupCount,
          ),
        );

    Widget ratingChip() => GestureDetector(
          onTap: () => _showRatingSheet(context),
          behavior: HitTestBehavior.opaque,
          child: _metaChip(
            icon: Icons.star_rounded,
            suffix: rating ?? '—',
            color: _ratingChip.color,
            shrinkSuffix: true,
          ),
        );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: quantityChip()),
              const SizedBox(width: 4),
              Expanded(child: valueChip()),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: expansionChip()),
              const SizedBox(width: 4),
              Expanded(child: ratingChip()),
            ],
          ),
          const SizedBox(height: 4),
          locationChip(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: quantityChip()),
            const SizedBox(width: 4),
            Expanded(child: valueChip()),
            const SizedBox(width: 4),
            Expanded(child: expansionChip()),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(flex: 3, child: locationChip()),
            const SizedBox(width: 4),
            Expanded(flex: 2, child: ratingChip()),
          ],
        ),
      ],
    );
  }

  TextStyle _chipTextStyle(Color color) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.15,
        color: color,
      );

  Widget _fittedChipText(String text, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        style: _chipTextStyle(color),
      ),
    );
  }

  Widget _metaChip({
    Key? key,
    IconData? icon,
    String? suffix,
    required Color color,
    bool shrinkSuffix = false,
    bool textOnly = false,
    int groupCount = 0,
  }) {
    return ClipRect(
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: textOnly
            ? _fittedChipText(suffix ?? '', color)
            : Row(
                children: [
                  if (icon != null) Icon(icon, size: 13, color: color),
                  if (suffix != null) ...[
                    const SizedBox(width: 2),
                    Expanded(
                      child: _fittedChipText(suffix, color),
                    ),
                  ],
                  if (groupCount > 0) ...[
                    Icon(Icons.group, size: 13, color: Colors.teal.shade600),
                    Flexible(
                      child: _fittedChipText(
                        '$groupCount',
                        Colors.teal.shade600,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
