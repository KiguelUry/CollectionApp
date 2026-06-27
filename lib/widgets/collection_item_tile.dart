import 'package:flutter/material.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../utils/boardgame_display.dart';
import '../utils/boardgame_collection_visibility.dart';
import '../utils/boardgame_expansions.dart';
import '../utils/friend_item_overlap.dart';
import '../utils/holder_label_utils.dart';
import '../utils/tcg_card_display.dart';
import 'boardgame_tile_inventory_sheets.dart';
import 'boardgame_tile_sheets.dart';
import 'bgg_network_image.dart';

/// Tuile grille pour un objet de collection (grisée si vendu).
class CollectionItemTile extends StatelessWidget {
  final CollectionItem item;
  final CollectionCategory category;
  final int totalQuantity;
  /// Exemplaires réellement possédés en collection (wishlist incluse).
  final int? ownedQuantity;
  final bool showDuplicateBadge;
  final bool showGroupBadge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final FriendOverlapKind? overlapKind;
  final bool coverFirst;
  final Map<String, String>? groupNamesById;
  /// Groupes pour le changement rapide de localisation (jeux de société).
  final List<CollectionGroup>? boardgameQuickEditGroups;
  /// Nombre d'objets par groupe (tri activité décroissante).
  final Map<String, int> groupActivityCounts;

  const CollectionItemTile({
    super.key,
    required this.item,
    required this.category,
    this.totalQuantity = 1,
    this.ownedQuantity,
    this.showDuplicateBadge = false,
    this.showGroupBadge = true,
    this.onTap,
    this.onLongPress,
    this.onDelete,
    this.overlapKind,
    this.coverFirst = false,
    this.groupNamesById,
    this.boardgameQuickEditGroups,
    this.groupActivityCounts = const {},
  });

  bool get _isGrayed =>
      item.isSold || (!item.isWishlist && item.quantity <= 0);

  bool get _isCard => category == CollectionCategory.card;

  bool get _isBoardgame => category == CollectionCategory.boardgame;

  int get _ownedQty =>
      ownedQuantity ?? (item.isWishlist ? 0 : totalQuantity);

  static const _metaRowHeight = 20.0;

  bool get _hasMetaIcons {
    if (_isBoardgame) return true;
    final qty = showDuplicateBadge && _ownedQty > 1;
    final group = showGroupBadge && _groupCount > 0 && !item.isSold;
    final expansions = _isBoardgame && ownedExpansionCount(item) > 0;
    final rating = _isBoardgame && _bggRatingLabel != null;
    final location = _isBoardgame && _locationChipLabel != null;
    return qty || group || expansions || rating || location;
  }

  @override
  Widget build(BuildContext context) {
    if (_isCard) {
      return _buildCardTile();
    }

    if (_isBoardgame) {
      final image = _buildBoardgameImageStack(context);
      final footer = !coverFirst ? _buildBoardgameFooter(context) : null;

      if (onTap == null && onLongPress == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            image,
            if (footer != null) footer,
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: image,
          ),
          if (footer != null) footer,
        ],
      );
    }

    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildImageStack(context)),
        if (!coverFirst)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: _isGrayed ? Colors.grey : null,
                  ),
                ),
                if (_subtitleLine != null)
                  Text(
                    _subtitleLine!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 10,
                    ),
                  ),
                if (_whereLine != null)
                  Text(
                    _whereLine!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 9,
                    ),
                  ),
                if (_metaIconsRow(context) != null) _metaIconsRow(context)!,
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 10,
                color: _isGrayed ? Colors.grey : null,
              ),
            ),
          ),
      ],
    );

    if (onTap == null && onLongPress == null) return child;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
  }

  Widget _buildBoardgameFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              height: 1.15,
              color: _isGrayed ? Colors.grey : null,
            ),
          ),
          if (_boardgameStatsLine != null)
            Text(
              _boardgameStatsLine!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
                height: 1.15,
              ),
            ),
          const SizedBox(height: 2),
          SizedBox(
            height: _metaRowHeight,
            width: double.infinity,
            child: _buildIconRowTop(context),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: _metaRowHeight,
            width: double.infinity,
            child: _buildIconRowBottom(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardgameImageStack(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: _buildImageStack(context),
    );
  }

  Widget _buildImageStack(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_isBoardgame)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(coverFirst ? 16 : 12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: coverFirst ? 0.14 : 0.08,
                  ),
                  blurRadius: coverFirst ? 12 : 6,
                  offset: Offset(0, coverFirst ? 5 : 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(coverFirst ? 16 : 12),
              child: _buildImage(),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(coverFirst ? 16 : 12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: coverFirst ? 0.14 : 0.08,
                  ),
                  blurRadius: coverFirst ? 12 : 6,
                  offset: Offset(0, coverFirst ? 5 : 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(coverFirst ? 16 : 12),
              child: _buildImage(),
            ),
          ),
        if (onDelete != null)
          Positioned(
            top: 4,
            right: 4,
            child: _quickDeleteButton(),
          ),
        if (_overlapBadge != null) _overlapBadge!,
        if (item.isOnLoan && !item.isSold)
          Positioned(
            top: 4,
            left: 4,
            child: _badge('Prêté', Colors.blue.shade700),
          ),
        if (item.isForSale && !item.isSold)
          Positioned(
            top: 4,
            left: item.isOnLoan ? 52 : 4,
            child: _badge('Vente', Colors.orange.shade800),
          ),
        if (item.isSold)
          Positioned(
            bottom: 4,
            left: 4,
            right: 4,
            child: _badge('Vendu', Colors.grey.shade700),
          ),
      ],
    );
  }

  Widget _buildCardTile() {
    final child = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 5, 4, 0),
                  child: Align(
                    alignment: Alignment.center,
                    child: AspectRatio(
                      aspectRatio: 63 / 88,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: _buildImage(),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showDuplicateBadge && _ownedQty > 1)
                  Positioned(
                    top: 4,
                    right: onDelete != null ? 32 : 4,
                    child: _badge('×$_ownedQty', Colors.deepPurple),
                  ),
                if (onDelete != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _quickDeleteButton(),
                  ),
                if (_overlapBadge != null) _overlapBadge!,
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                    color: _isGrayed ? Colors.grey : Colors.black87,
                  ),
                ),
                if (_cardSubtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _cardSubtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 7,
                      height: 1.05,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null && onLongPress == null) return child;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(6),
      child: child,
    );
  }

  String? get _cardSubtitle => tcgCollectionItemSubtitle(item);

  String? get _boardgameStatsLine {
    if (!_isBoardgame) return null;
    final parts = <String>[];
    final players = formatPlayerCount(item.minPlayers, item.maxPlayers);
    if (players != null) parts.add(players);
    final time = formatPlayingTime(item.playingTime);
    if (time != null) parts.add(time);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get _subtitleLine {
    if (category == CollectionCategory.boardgame) {
      final expansionOf = boardgameExpansionOfLabel(item);
      if (expansionOf != null) {
        return 'Extension de $expansionOf';
      }
      final parts = <String>[];
      final players = formatPlayerCount(item.minPlayers, item.maxPlayers);
      if (players != null) parts.add(players);
      final time = formatPlayingTime(item.playingTime);
      if (time != null) parts.add(time);
      return parts.isEmpty ? null : parts.join(' · ');
    }
    return item.listSubtitle;
  }

  String? get _locationChipLabel {
    if (!_isBoardgame) return null;
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
      _isBoardgame ? formatBggRatingChipLabel(item.metadata?['bgg_avg_rating']) : null;

  String? get _whereLine {
    if (item.locationLabel == null || item.locationLabel!.trim().isEmpty) {
      return null;
    }
    return item.locationLabel;
  }

  int get _groupCount {
    final extra = item.metadata?['group_ids'];
    if (extra is List && extra.isNotEmpty) return extra.length;
    return item.groupId != null ? 1 : 0;
  }

  Future<void> _showQuantitySheet(BuildContext context) {
    return showBoardgameTileQuantitySheet(
      context,
      item: item,
      ownedQuantity: _ownedQty,
      readOnly: boardgameQuickEditGroups == null,
    );
  }

  Future<void> _showGroupSheet(BuildContext context) {
    return showBoardgameTileGroupSheet(
      context,
      item: item,
      groups: boardgameQuickEditGroups ?? const [],
      groupActivityCounts: groupActivityCounts,
      readOnly: boardgameQuickEditGroups == null,
    );
  }

  Future<void> _showExpansionSheet(BuildContext context) {
    return showBoardgameTileExpansionSheet(
      context,
      item: item,
      readOnly: boardgameQuickEditGroups == null,
    );
  }

  Future<void> _showRatingSheet(BuildContext context) {
    return showBoardgameTileRatingSheet(
      context,
      item: item,
      readOnly: boardgameQuickEditGroups == null,
    );
  }

  Future<void> _showLocationSheet(BuildContext context) {
    return showBoardgameTileLocationSheet(
      context,
      item: item,
      groups: boardgameQuickEditGroups ?? const [],
      readOnly: boardgameQuickEditGroups == null,
    );
  }

  Widget _buildIconRowTop(BuildContext context) {
    final groupCount = showGroupBadge && !item.isSold ? _groupCount : 0;
    final expansionCount = ownedExpansionCount(item);

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _showQuantitySheet(context),
            behavior: HitTestBehavior.opaque,
            child: _metaChip(
              icon: Icons.layers_outlined,
              suffix: '$_ownedQty',
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
            onTap: () => _showExpansionSheet(context),
            behavior: HitTestBehavior.opaque,
            child: _metaChip(
              icon: Icons.extension_outlined,
              suffix: '$expansionCount',
              color: Colors.green.shade600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconRowBottom(BuildContext context) {
    final location = _locationChipLabel;
    final rating = _bggRatingLabel;

    return Row(
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
    );
  }

  Widget? _metaIconsRow(BuildContext context) {
    if (!_hasMetaIcons) return null;

    final qty = showDuplicateBadge && _ownedQty > 1;
    final group = showGroupBadge && _groupCount > 0 && !item.isSold;
    final expansions = _isBoardgame && ownedExpansionCount(item) > 0;
    final rating = _bggRatingLabel;
    final location = _locationChipLabel;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (qty)
          _metaChip(
            icon: Icons.layers_outlined,
            suffix: '$_ownedQty',
            color: Colors.lightBlue.shade600,
          ),
        if (qty && (group || expansions || rating != null || location != null))
          const SizedBox(width: 4),
        if (group)
          GestureDetector(
            onTap: () => _showGroupSheet(context),
            behavior: HitTestBehavior.opaque,
            child: _metaChip(
              icon: _groupCount > 1 ? Icons.groups : Icons.group_outlined,
              suffix: _groupCount > 1 ? '$_groupCount' : null,
              color: Colors.teal.shade500,
            ),
          ),
        if (group && (expansions || rating != null || location != null))
          const SizedBox(width: 4),
        if (expansions)
          GestureDetector(
            onTap: () => _showExpansionSheet(context),
            behavior: HitTestBehavior.opaque,
            child: _metaChip(
              icon: Icons.extension_outlined,
              suffix: '${ownedExpansionCount(item)}',
              color: Colors.green.shade600,
            ),
          ),
        if (expansions && (rating != null || location != null))
          const SizedBox(width: 4),
        if (rating != null)
          _metaChip(
            icon: Icons.star_rounded,
            suffix: rating,
            color: Colors.amber.shade700,
          ),
        if (rating != null && location != null) const SizedBox(width: 4),
        if (location != null)
          _metaChip(
            icon: Icons.place_outlined,
            suffix: location,
            color: Colors.deepOrange.shade400,
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

  Widget _quickDeleteButton() {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onDelete,
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(
            Icons.delete_outline,
            size: 15,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    Widget image;
    if (item.imageUrl != null) {
      final isBook = category == CollectionCategory.book;
      final isCard = category == CollectionCategory.card;
      final isBoardgame = category == CollectionCategory.boardgame;
      image = BggNetworkImage(
        key: ValueKey(item.id),
        url: item.imageUrl!,
        fit: isCard ? BoxFit.contain : BoxFit.cover,
        bookCover: isBook,
        boxedCover: isBoardgame,
        largeSource: !isBook && !isCard,
      );
    } else {
      image = ColoredBox(
        color: _isCard ? Colors.transparent : Colors.grey.shade200,
        child: Icon(category.icon, color: Colors.grey),
      );
    }

    if (_isGrayed) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 0.45, 0,
        ]),
        child: image,
      );
    }

    return image;
  }

  Positioned? get _overlapBadge {
    final kind = overlapKind;
    if (kind == null || kind == FriendOverlapKind.none) return null;
    final inColl = kind == FriendOverlapKind.inCollection;
    return Positioned(
      top: 4,
      left: 4,
      child: _badge(inColl ? 'Toi' : '♥', inColl ? Colors.green.shade700 : Colors.amber.shade800),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
