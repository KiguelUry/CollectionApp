import 'package:flutter/material.dart';

import '../bgg_network_image.dart';

/// Tuile catalogue : fine cellule blanche + bandeau gris avec le nom.
class TcgCatalogCardTile extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final Color accent;
  final bool owned;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback? onQuickAdd;

  const TcgCatalogCardTile({
    super.key,
    required this.name,
    this.imageUrl,
    required this.accent,
    this.owned = false,
    this.selected = false,
    this.selectionMode = false,
    required this.onTap,
    this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? accent
                  : Colors.grey.shade300,
              width: selected ? 2 : 0.8,
            ),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(5),
                  ),
                ),
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 8,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
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
