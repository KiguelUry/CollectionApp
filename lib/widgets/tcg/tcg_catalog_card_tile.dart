import 'package:flutter/material.dart';

import '../bgg_network_image.dart';

/// Tuile catalogue : image + infos (bloc, série, numéro).
class TcgCatalogCardTile extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final List<String> detailLines;
  final Color accent;
  final bool owned;
  final bool inWishlist;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onQuickAdd;
  final VoidCallback? onQuickWishlist;

  const TcgCatalogCardTile({
    super.key,
    required this.name,
    this.imageUrl,
    this.detailLines = const [],
    required this.accent,
    this.owned = false,
    this.inWishlist = false,
    this.selected = false,
    this.selectionMode = false,
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
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? accent : Colors.grey.shade300,
              width: selected ? 2 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 11,
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
                              child: imageUrl != null && imageUrl!.isNotEmpty
                                  ? BggNetworkImage(
                                      url: imageUrl!,
                                      fit: BoxFit.contain,
                                    )
                                  : Icon(
                                      Icons.style,
                                      color: accent.withValues(alpha: 0.35),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (selectionMode)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: selected ? accent : Colors.grey.shade500,
                          size: 20,
                        ),
                      ),
                    if (owned && !selectionMode)
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
                    if (onQuickWishlist != null && !selectionMode && !owned)
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
                    if (onQuickAdd != null && !selectionMode)
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
              Flexible(
                flex: 9,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(5),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 7.5,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      for (final line in detailLines.take(3))
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 6,
                            height: 1.1,
                            color: Colors.grey.shade800,
                          ),
                        ),
                    ],
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
