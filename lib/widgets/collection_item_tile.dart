import 'package:flutter/material.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/boardgame_display.dart';
import '../utils/boardgame_collection_visibility.dart';
import '../utils/boardgame_expansions.dart';
import '../utils/friend_item_overlap.dart';
import '../utils/tcg_card_display.dart';
import 'bgg_network_image.dart';

/// Tuile grille pour un objet de collection (grisée si vendu).
class CollectionItemTile extends StatelessWidget {
  final CollectionItem item;
  final CollectionCategory category;
  final int totalQuantity;
  final bool showDuplicateBadge;
  final bool showGroupBadge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final FriendOverlapKind? overlapKind;
  final bool coverFirst;

  const CollectionItemTile({
    super.key,
    required this.item,
    required this.category,
    this.totalQuantity = 1,
    this.showDuplicateBadge = false,
    this.showGroupBadge = true,
    this.onTap,
    this.onLongPress,
    this.onDelete,
    this.overlapKind,
    this.coverFirst = false,
  });

  bool get _isGrayed => item.isSold;

  bool get _isCard => category == CollectionCategory.card;

  @override
  Widget build(BuildContext context) {
    if (_isCard) {
      return _buildCardTile();
    }

    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (category == CollectionCategory.boardgame)
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
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
              if (showDuplicateBadge && totalQuantity > 1)
                Positioned(
                  top: 4,
                  right: onDelete != null ? 32 : 4,
                  child: _badge('×$totalQuantity', Colors.deepPurple),
                ),
              if (onDelete != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: _quickDeleteButton(),
                ),
              if (category == CollectionCategory.boardgame &&
                  ownedExpansionCount(item) > 0)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: _expansionBadge(ownedExpansionCount(item)),
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
              if (showGroupBadge &&
                  item.isGroupOwned &&
                  !item.isSold &&
                  !(category == CollectionCategory.boardgame &&
                      ownedExpansionCount(item) > 0))
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Tooltip(
                    message: item.groupName ?? 'Collection de groupe',
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade700,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.groups,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!coverFirst) const SizedBox(height: 6),
        if (!coverFirst)
          Column(
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
            ],
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
                if (showDuplicateBadge && totalQuantity > 1)
                  Positioned(
                    top: 4,
                    right: onDelete != null ? 32 : 4,
                    child: _badge('×$totalQuantity', Colors.deepPurple),
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

  String? get _whereLine {
    if (item.locationLabel == null || item.locationLabel!.trim().isEmpty) {
      return null;
    }
    return item.locationLabel;
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

  Widget _expansionBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.shade700,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_circle_outline, size: 12, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
