import 'package:flutter/material.dart';

import '../bgg_network_image.dart';

/// Tuile catalogue générique (jeux de société, vinyles…) : image + ♥ / +.
class CatalogItemTile extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final String? subtitle;
  final Color accent;
  final bool owned;
  final bool inWishlist;
  final double aspectRatio;
  final IconData placeholderIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onQuickAdd;
  final VoidCallback? onQuickWishlist;

  const CatalogItemTile({
    super.key,
    required this.name,
    this.imageUrl,
    this.subtitle,
    required this.accent,
    this.owned = false,
    this.inWishlist = false,
    this.aspectRatio = 1,
    this.placeholderIcon = Icons.casino_outlined,
    required this.onTap,
    this.onLongPress,
    this.onQuickAdd,
    this.onQuickWishlist,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
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
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: Align(
                        alignment: Alignment.center,
                        child: AspectRatio(
                          aspectRatio: aspectRatio,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: imageUrl != null && imageUrl!.isNotEmpty
                                  ? BggNetworkImage(
                                      url: imageUrl!,
                                      fit: BoxFit.contain,
                                    )
                                  : Icon(
                                      placeholderIcon,
                                      color: accent.withValues(alpha: 0.35),
                                      size: 36,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (owned)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 11,
                          ),
                        ),
                      ),
                    if (onQuickWishlist != null && !owned)
                      Positioned(
                        top: 2,
                        left: 2,
                        child: Material(
                          color: inWishlist
                              ? Colors.red.shade600
                              : Colors.white.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            onTap: onQuickWishlist,
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Icon(
                                inWishlist
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 14,
                                color: inWishlist
                                    ? Colors.white
                                    : Colors.red.shade600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (onQuickAdd != null && !owned)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Material(
                          color: accent,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            onTap: onQuickAdd,
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.all(3),
                              child: Icon(
                                Icons.add,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8.5,
                          height: 1.1,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
