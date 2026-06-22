import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_volume.dart';
import '../../widgets/collection_cover_image.dart';

/// Cellule visuelle d'un tome (Possédé × Lu).
class BookVolumeCell extends StatelessWidget {
  static const coverAspectRatio = 2 / 3;

  final BookVolumeSlot slot;
  final Color accent;
  final int coverEpoch;
  final VoidCallback? onCenterTap;
  final VoidCallback? onLongPress;
  final Future<void> Function()? onOwnedTap;
  final Future<void> Function()? onReadTap;

  const BookVolumeCell({
    super.key,
    required this.slot,
    this.accent = BookAccent.primary,
    this.coverEpoch = 0,
    this.onCenterTap,
    this.onLongPress,
    this.onOwnedTap,
    this.onReadTap,
  });

  bool get _owned =>
      slot.item != null && !slot.item!.isWishlist;

  bool get _read =>
      (slot.item?.isRead ?? false) || slot.volume.isRead;

  @override
  Widget build(BuildContext context) {
    final cover = slot.volume.coverUrl;
    final title = slot.volume.displayTitle;

    return Material(
      color: _owned ? accent.withValues(alpha: 0.08) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onCenterTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: coverAspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: cover != null && cover.isNotEmpty
                          ? CollectionCoverImage(
                              key: ValueKey('${slot.volume.id}-$cover-$coverEpoch'),
                              url: cover,
                              bookCover: true,
                              largeSource: true,
                              fit: BoxFit.cover,
                            )
                          : _placeholder(slot.volume.displayNumber),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      height: 1.2,
                      color: _owned ? accent : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: _StatusBadge(
                icon: Icons.home_rounded,
                active: _owned,
                activeColor: accent,
                onTap: onOwnedTap,
              ),
            ),
            Positioned(
              top: 2,
              left: 2,
              child: _StatusBadge(
                icon: Icons.visibility_rounded,
                active: _read,
                activeColor: Colors.amber.shade800,
                onTap: onReadTap,
              ),
            ),
            if (slot.volume.isManualPlaceholder)
              Positioned(
                bottom: 4,
                right: 4,
                child: Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: accent.withValues(alpha: 0.8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(String n) {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: Text(
        n,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color activeColor;
  final Future<void> Function()? onTap;

  const _StatusBadge({
    required this.icon,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? activeColor : Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () async {
                await onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}
