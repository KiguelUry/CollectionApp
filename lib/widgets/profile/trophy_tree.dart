import 'package:flutter/material.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../collection_cover_image.dart';

/// Arbre stylisé : tronc au centre, jusqu'à 6 trophées sur les branches.
class TrophyTree extends StatelessWidget {
  final List<CollectionItem?> slots;
  final Color accentColor;
  final bool editable;
  final void Function(int index)? onSlotTap;

  const TrophyTree({
    super.key,
    required this.slots,
    required this.accentColor,
    this.editable = false,
    this.onSlotTap,
  });

  static const _slotSize = 56.0;
  static const _treeHeight = 300.0;

  /// Positions normalisées (x, y) des 6 emplacements sur l'arbre.
  static const _branchSlots = <Offset>[
    Offset(0.50, 0.06),
    Offset(0.18, 0.20),
    Offset(0.82, 0.20),
    Offset(0.10, 0.38),
    Offset(0.90, 0.38),
    Offset(0.50, 0.28),
  ];

  @override
  Widget build(BuildContext context) {
    final items = List<CollectionItem?>.generate(
      6,
      (i) => i < slots.length ? slots[i] : null,
    );

    return SizedBox(
      height: _treeHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = _treeHeight;
          final trunkX = w * 0.5;
          final trunkTop = h * 0.32;
          final trunkBottom = h * 0.88;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(w, h),
                painter: _TreeBranchesPainter(
                  accentColor: accentColor,
                  trunkX: trunkX,
                  trunkTop: trunkTop,
                  trunkBottom: trunkBottom,
                  branchEnds: [
                    for (final pos in _branchSlots)
                      Offset(pos.dx * w, pos.dy * h),
                  ],
                ),
              ),
              Positioned(
                left: trunkX - 28,
                top: trunkTop - 8,
                child: Icon(
                  Icons.park_rounded,
                  size: 56,
                  color: accentColor.withValues(alpha: 0.35),
                ),
              ),
              for (var i = 0; i < 6; i++)
                Positioned(
                  left: _branchSlots[i].dx * w - _slotSize / 2,
                  top: _branchSlots[i].dy * h - _slotSize / 2,
                  child: _TrophySlot(
                    item: items[i],
                    size: _slotSize,
                    editable: editable,
                    onTap: onSlotTap != null ? () => onSlotTap!(i) : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TrophySlot extends StatelessWidget {
  final CollectionItem? item;
  final double size;
  final bool editable;
  final VoidCallback? onTap;

  const _TrophySlot({
    required this.item,
    required this.size,
    required this.editable,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Material(
      elevation: item != null ? 3 : 0,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      color: item != null ? Colors.white : Colors.grey.shade200,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: item != null ? Colors.amber.shade600 : Colors.grey.shade400,
              width: item != null ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: item != null
              ? CollectionCoverImage(
                  url: item!.imageUrl ?? '',
                  width: size,
                  height: size,
                  bookCover: item!.category == CollectionCategory.book,
                )
              : Icon(
                  editable ? Icons.add : Icons.emoji_events_outlined,
                  color: Colors.grey.shade500,
                  size: 28,
                ),
        ),
      ),
    );

    if (item == null) return child;

    return Tooltip(
      message: item!.title,
      child: child,
    );
  }
}

class _TreeBranchesPainter extends CustomPainter {
  final Color accentColor;
  final double trunkX;
  final double trunkTop;
  final double trunkBottom;
  final List<Offset> branchEnds;

  _TreeBranchesPainter({
    required this.accentColor,
    required this.trunkX,
    required this.trunkTop,
    required this.trunkBottom,
    required this.branchEnds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trunkPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.45)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(trunkX, trunkBottom),
      Offset(trunkX, trunkTop),
      trunkPaint,
    );

    final branchPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.35)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final crownY = trunkTop + 8;
    for (final end in branchEnds) {
      canvas.drawLine(Offset(trunkX, crownY), end, branchPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TreeBranchesPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}
