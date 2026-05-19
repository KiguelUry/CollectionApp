import 'package:flutter/material.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import 'bgg_network_image.dart';

/// Tuile grille pour un objet de collection (grisée si vendu).
class CollectionItemTile extends StatelessWidget {
  final CollectionItem item;
  final CollectionCategory category;
  final int totalQuantity;
  final bool showDuplicateBadge;
  final bool showGroupBadge;
  final VoidCallback? onTap;

  const CollectionItemTile({
    super.key,
    required this.item,
    required this.category,
    this.totalQuantity = 1,
    this.showDuplicateBadge = false,
    this.showGroupBadge = true,
    this.onTap,
  });

  bool get _isGrayed => item.isSold;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildImage(),
                ),
              ),
              if (showDuplicateBadge && totalQuantity > 1)
                Positioned(
                  top: 4,
                  right: 4,
                  child: _badge('×$totalQuantity', Colors.deepPurple),
                ),
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
              if (showGroupBadge && item.isGroupOwned && !item.isSold)
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
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
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
              if (item.listSubtitle != null)
                Text(
                  item.listSubtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 9,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (onTap == null) return child;

    return InkWell(onTap: onTap, child: child);
  }

  Widget _buildImage() {
    Widget image;
    if (item.imageUrl != null) {
      final isBook = category == CollectionCategory.book;
      image = BggNetworkImage(
        url: item.imageUrl!,
        bookCover: isBook,
        largeSource: !isBook,
      );
    } else {
      image = Container(
        color: Colors.grey.shade200,
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
