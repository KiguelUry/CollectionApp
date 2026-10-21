import 'package:flutter/material.dart';

import '../../models/collection_item.dart';
import '../../services/boardgame_market_service.dart';
import '../../utils/boardgame_display.dart';
import '../../utils/wishlist_market_metadata.dart';
import '../boardgame_tile_inventory_sheets.dart';
import '../boardgame_tile_sheets.dart';

/// Badges wishlist — même échelle / puce € que la collection (2 + 1 sur GSM).
class WishlistTileMetaIcons extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;

  const WishlistTileMetaIcons({
    super.key,
    required this.item,
    this.readOnly = false,
  });

  @override
  State<WishlistTileMetaIcons> createState() => _WishlistTileMetaIconsState();
}

class _WishlistTileMetaIconsState extends State<WishlistTileMetaIcons> {
  static const _rowHeight = 20.0;
  bool _fetchingMeta = false;

  @override
  void initState() {
    super.initState();
    _prefetchMissingMetadata();
  }

  @override
  void didUpdateWidget(covariant WishlistTileMetaIcons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.metadata != widget.item.metadata) {
      _prefetchMissingMetadata();
    }
  }

  Future<void> _prefetchMissingMetadata() async {
    if (_fetchingMeta) return;
    final missingPrices =
        marketSecondhandPriceFromMetadata(widget.item.metadata) == null &&
            marketNewPriceMinFromMetadata(widget.item.metadata) == null;
    final missingExt =
        bggExpansionCountFromMetadata(widget.item.metadata) == null;
    if (!missingPrices && !missingExt) return;
    _fetchingMeta = true;
    try {
      await BoardgameMarketService.enrichItemMetadata(widget.item);
    } catch (_) {
    } finally {
      _fetchingMeta = false;
    }
  }

  String get _valueChipLabel {
    final avg = marketPriceAvgFromMetadata(widget.item.metadata);
    if (avg != null && avg > 0) {
      return '~${formatEuroChip(avg, compact: false)}';
    }
    final market = marketSecondhandPriceFromMetadata(widget.item.metadata);
    if (market != null) return '~${formatEuroChip(market, compact: false)}';
    final neu = marketNewPriceMinFromMetadata(widget.item.metadata);
    if (neu != null) return '~${formatEuroChip(neu, compact: false)}';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final extCount = bggExpansionCountFromMetadata(widget.item.metadata) ?? 0;
    final rating =
        formatBggRatingChipLabel(widget.item.metadata?['bgg_avg_rating']);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _rowHeight,
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: _chip(
                  icon: Icons.extension_outlined,
                  suffix: '$extCount',
                  color: Colors.green.shade600,
                  onTap: () => showBoardgameTileExpansionSheet(
                    context,
                    item: widget.item,
                    readOnly: widget.readOnly,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _chip(
                  suffix: _valueChipLabel,
                  color: Colors.teal.shade500,
                  textOnly: true,
                  onTap: () => showBoardgameTileValueSheet(
                    context,
                    item: widget.item,
                    readOnly: widget.readOnly,
                    showPurchaseBlock: false,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: _rowHeight,
          width: double.infinity,
          child: _chip(
            icon: Icons.star_rounded,
            suffix: rating ?? '—',
            color: Colors.amber.shade700,
            shrinkSuffix: true,
            onTap: () => showBoardgameTileRatingSheet(
              context,
              item: widget.item,
              readOnly: widget.readOnly,
            ),
          ),
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

  Widget _chip({
    IconData? icon,
    required String suffix,
    required Color color,
    bool shrinkSuffix = false,
    bool textOnly = false,
    VoidCallback? onTap,
  }) {
    final child = ClipRect(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: textOnly
            ? _fittedChipText(suffix, color)
            : Row(
                children: [
                  if (icon != null) Icon(icon, size: 13, color: color),
                  const SizedBox(width: 2),
                  Expanded(child: _fittedChipText(suffix, color)),
                ],
              ),
      ),
    );
    if (onTap == null) return child;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}
